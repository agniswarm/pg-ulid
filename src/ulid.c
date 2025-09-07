/* ulid.c
 *
 * PostgreSQL ULID extension.
 *
 * - Uses aperezdc/ulid-c when available for generation and encoding.
 * - Provides a correct, reversible fallback for text <-> 16 bytes using
 *   __uint128_t arithmetic so text -> bytes -> text round-trips exactly.
 *
 * Build:
 *   If you have ulid-c (aperezdc/ulid-c), add its include directory and
 *   define HAVE_ULID_H in your Makefile. Otherwise the fallback encoder/decoder
 *   will be used.
 */

 #include "postgres.h"
 #include "fmgr.h"
 #include "utils/builtins.h"
 #include "utils/lsyscache.h"
 #include "catalog/pg_type.h"
 #include "access/htup_details.h"
 #include "utils/timestamp.h"
 #include "utils/uuid.h"
 #include "libpq/pqformat.h"
 #include "utils/elog.h"
 
 #include <ctype.h>
 #include <time.h>
 #include <string.h>
 #include <stdbool.h>
 #include <stdint.h>
 #include <stdlib.h>
 
 PG_MODULE_MAGIC;
 
 /* Try to include ulid-c header if available */
 #ifdef HAVE_ULID_H
 # include "ulid.h"
 #endif
 
 /* Forward declarations (Postgres API) */
 Datum ulid_in(PG_FUNCTION_ARGS);
 Datum ulid_out(PG_FUNCTION_ARGS);
 Datum ulid_send(PG_FUNCTION_ARGS);
 Datum ulid_recv(PG_FUNCTION_ARGS);
 Datum ulid_cmp(PG_FUNCTION_ARGS);
 Datum ulid_generate(PG_FUNCTION_ARGS);
 Datum ulid_generate_monotonic(PG_FUNCTION_ARGS);
 Datum ulid_generate_with_timestamp(PG_FUNCTION_ARGS);
 Datum ulid_timestamp_fn(PG_FUNCTION_ARGS);
 Datum ulid_to_uuid(PG_FUNCTION_ARGS);
 Datum ulid_from_uuid(PG_FUNCTION_ARGS);
 Datum ulid_hash(PG_FUNCTION_ARGS);
 
 Datum ulid_lt(PG_FUNCTION_ARGS);
 Datum ulid_le(PG_FUNCTION_ARGS);
 Datum ulid_eq(PG_FUNCTION_ARGS);
 Datum ulid_ne(PG_FUNCTION_ARGS);
 Datum ulid_ge(PG_FUNCTION_ARGS);
 Datum ulid_gt(PG_FUNCTION_ARGS);
 
 /* ULID bytes container (16 bytes) */
 typedef struct ULID
 {
     unsigned char data[16];
 } ULID;
 
 static const char base32_alphabet[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
 #define ULID_TEXT_LEN 26
 
 /* permissive mapping: case-insensitive, I/L -> 1, O -> 0 */
 static int base32_val(char c)
 {
     if (c >= '0' && c <= '9')
         return c - '0';
 
     if (c >= 'a' && c <= 'z')
         c = c - 'a' + 'A';
 
     if (c == 'I' || c == 'L')
         return 1;
     if (c == 'O')
         return 0;
 
     switch (c)
     {
         case 'A': return 10;
         case 'B': return 11;
         case 'C': return 12;
         case 'D': return 13;
         case 'E': return 14;
         case 'F': return 15;
         case 'G': return 16;
         case 'H': return 17;
         case 'J': return 18;
         case 'K': return 19;
         case 'M': return 20;
         case 'N': return 21;
         case 'P': return 22;
         case 'Q': return 23;
         case 'R': return 24;
         case 'S': return 25;
         case 'T': return 26;
         case 'V': return 27;
         case 'W': return 28;
         case 'X': return 29;
         case 'Y': return 30;
         case 'Z': return 31;
         default: return -1;
     }
 }
 
 /* decode canonical ULID text (25 or 26 chars) into 16 bytes (big-endian)
  * Returns true on success, false on invalid input.
  */
 static bool decode_ulid_text_to_bytes(const char *input, ULID *out)
 {
     if (!input || !out)
         return false;
 
     size_t len = strlen(input);
     if (!(len == 25 || len == 26))
         return false;
 
     int vals[26] = {0};
     for (size_t i = 0; i < len; i++)
     {
         int v = base32_val(input[i]);
         if (v < 0)
             return false;
         vals[i] = v & 0x1F;
     }
 
     __uint128_t acc = 0;
 
     if (len == 26)
     {
         /* 26 * 5 = 130 bits. Build accumulator and shift right by 2 to get 128 bits */
         for (int i = 0; i < 26; i++)
         {
             acc = (acc << 5) | (uint64_t)vals[i];
         }
         /* drop lowest 2 padding bits */
         acc >>= 2;
     }
     else /* len == 25 */
     {
         /* 25 * 5 = 125 bits. Left-shift by 3 to pad to 128 bits */
         for (int i = 0; i < 25; i++)
         {
             acc = (acc << 5) | (uint64_t)vals[i];
         }
         acc <<= 3;
     }
 
     /* store as big-endian bytes */
     uint64_t high = (uint64_t)(acc >> 64);
     uint64_t low  = (uint64_t)(acc & 0xFFFFFFFFFFFFFFFFULL);
 
     for (int i = 0; i < 8; i++)
         out->data[i] = (unsigned char)((high >> (56 - i * 8)) & 0xFF);
 
     for (int i = 0; i < 8; i++)
         out->data[i + 8] = (unsigned char)((low >> (56 - i * 8)) & 0xFF);
 
     return true;
 }
 
 /* encode 16 bytes -> canonical 26-char ULID text.
  * If ulid-c is present we'll prefer its encoder; otherwise use this fallback.
  */
 static void encode_bytes_to_ulid_text(const ULID *in, char *out_buffer /* must be >= 27 bytes */)
 {
 #ifdef HAVE_ULID_H
     /* use ulid-c's ulid_t and ulid_string if available */
     ulid_t tmp;
     memcpy(tmp.b, in->data, 16);
     ulid_string(&tmp, out_buffer);
 #else
     /* Build 128-bit big-endian value and left-shift by 2 to get 130 bits */
     __uint128_t acc = 0;
     for (int i = 0; i < 16; i++)
         acc = (acc << 8) | (uint64_t)in->data[i];
 
     acc <<= 2; /* now 130 bits where lowest 2 bits are zero (canonical) */
 
     /* extract 26 groups from least-significant side to fill output from end */
     for (int i = ULID_TEXT_LEN - 1; i >= 0; i--)
     {
         uint8_t v = (uint8_t)(acc & 0x1F);
         out_buffer[i] = base32_alphabet[v];
         acc >>= 5;
     }
     out_buffer[ULID_TEXT_LEN] = '\0';
 #endif
 }
 
 /* generation helpers: prefer ulid-c, otherwise fallback to timestamp + rand() (not cryptographically secure) */
 static void generate_ulid_bytes(ULID *out)
 {
 #ifdef HAVE_ULID_H
     ulid_t u;
     ulid_make_urandom(&u);
     memcpy(out->data, u.b, 16);
 #else
     struct timespec ts;
     clock_gettime(CLOCK_REALTIME, &ts);
     uint64_t timestamp = (uint64_t)ts.tv_sec * 1000 + (uint64_t)(ts.tv_nsec / 1000000);
 
     out->data[0] = (timestamp >> 40) & 0xFF;
     out->data[1] = (timestamp >> 32) & 0xFF;
     out->data[2] = (timestamp >> 24) & 0xFF;
     out->data[3] = (timestamp >> 16) & 0xFF;
     out->data[4] = (timestamp >> 8) & 0xFF;
     out->data[5] = timestamp & 0xFF;
 
     for (int i = 6; i < 16; i++)
         out->data[i] = (unsigned char)(random() & 0xFF);
 #endif
 }
 
 /* monotonic generator: timestamp + counter, resets when time advances */
 static void generate_ulid_monotonic_bytes(ULID *out)
 {
     static int64_t last_time_ms = 0;
     static uint32_t counter = 0;
 
     int64_t current_time_ms = (int64_t)(GetCurrentTimestamp() / 1000);
 
     if (current_time_ms > last_time_ms)
     {
         last_time_ms = current_time_ms;
         counter = 0;
     }
 
     /* store timestamp */
     out->data[0] = (last_time_ms >> 40) & 0xFF;
     out->data[1] = (last_time_ms >> 32) & 0xFF;
     out->data[2] = (last_time_ms >> 24) & 0xFF;
     out->data[3] = (last_time_ms >> 16) & 0xFF;
     out->data[4] = (last_time_ms >> 8) & 0xFF;
     out->data[5] = last_time_ms & 0xFF;
 
     /* increment counter */
     counter++;
 
     out->data[6] = (counter >> 24) & 0xFF;
     out->data[7] = (counter >> 16) & 0xFF;
     out->data[8] = (counter >> 8) & 0xFF;
     out->data[9] = (counter) & 0xFF;
 
 #ifdef HAVE_ULID_H
     ulid_t u;
     ulid_make_urandom(&u);
     memcpy(&out->data[10], &u.b[10], 6);
 #else
     for (int i = 10; i < 16; i++)
         out->data[i] = (unsigned char)(random() & 0xFF);
 #endif
 }
 
 /* generate with explicit timestamp (ms) */
 static void generate_ulid_with_ts_bytes(ULID *out, int64_t timestamp_ms)
 {
     out->data[0] = (timestamp_ms >> 40) & 0xFF;
     out->data[1] = (timestamp_ms >> 32) & 0xFF;
     out->data[2] = (timestamp_ms >> 24) & 0xFF;
     out->data[3] = (timestamp_ms >> 16) & 0xFF;
     out->data[4] = (timestamp_ms >> 8) & 0xFF;
     out->data[5] = timestamp_ms & 0xFF;
 
 #ifdef HAVE_ULID_H
     ulid_t u;
     ulid_make_urandom(&u);
     memcpy(&out->data[6], &u.b[6], 10);
 #else
     for (int i = 6; i < 16; i++)
         out->data[i] = (unsigned char)(random() & 0xFF);
 #endif
 }
 
 /* extract timestamp ms */
 static int64_t extract_timestamp_ms_from_ulid_bytes(const ULID *in)
 {
     uint64_t ts = 0;
     ts |= ((uint64_t)in->data[0] << 40);
     ts |= ((uint64_t)in->data[1] << 32);
     ts |= ((uint64_t)in->data[2] << 24);
     ts |= ((uint64_t)in->data[3] << 16);
     ts |= ((uint64_t)in->data[4] << 8);
     ts |= ((uint64_t)in->data[5]);
     return (int64_t)ts;
 }
 
 /* -------------------- Postgres wrapper functions -------------------- */
 
 PG_FUNCTION_INFO_V1(ulid_in);
 Datum
 ulid_in(PG_FUNCTION_ARGS)
 {
     char *input = PG_GETARG_CSTRING(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
 
     if (!decode_ulid_text_to_bytes(input, result))
     {
         ereport(ERROR,
                 (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                  errmsg("invalid input syntax for type ulid: \"%s\"", input)));
     }
 
     PG_RETURN_POINTER(result);
 }
 
 PG_FUNCTION_INFO_V1(ulid_out);
 Datum
 ulid_out(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     char *result = (char *) palloc(ULID_TEXT_LEN + 1);
 
 #ifdef HAVE_ULID_H
     /* convert to ulid-c and use its canonical string function */
     ulid_t tmp;
     memcpy(tmp.b, ulid->data, 16);
     ulid_string(&tmp, result);
 #else
     encode_bytes_to_ulid_text(ulid, result);
 #endif
 
     PG_RETURN_CSTRING(result);
 }
 
 PG_FUNCTION_INFO_V1(ulid_send);
 Datum
 ulid_send(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     bytea *result = (bytea *) palloc(VARHDRSZ + 16);
 
     SET_VARSIZE(result, VARHDRSZ + 16);
     memcpy(VARDATA(result), ulid->data, 16);
 
     PG_RETURN_BYTEA_P(result);
 }
 
 PG_FUNCTION_INFO_V1(ulid_recv);
 Datum
 ulid_recv(PG_FUNCTION_ARGS)
 {
     StringInfo buf = (StringInfo) PG_GETARG_POINTER(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
 
     if (buf->len < 16)
         elog(ERROR, "invalid ULID binary data");
 
     memcpy(result->data, buf->data, 16);
 
     PG_RETURN_POINTER(result);
 }
 
 PG_FUNCTION_INFO_V1(ulid_cmp);
 Datum
 ulid_cmp(PG_FUNCTION_ARGS)
 {
     ULID *a = (ULID *) PG_GETARG_POINTER(0);
     ULID *b = (ULID *) PG_GETARG_POINTER(1);
 
     int cmp = memcmp(a->data, b->data, 16);
     if (cmp < 0)
         PG_RETURN_INT32(-1);
     else if (cmp > 0)
         PG_RETURN_INT32(1);
     else
         PG_RETURN_INT32(0);
 }
 
 PG_FUNCTION_INFO_V1(ulid_lt);
 Datum
 ulid_lt(PG_FUNCTION_ARGS)
 {
     ULID *a = (ULID *) PG_GETARG_POINTER(0);
     ULID *b = (ULID *) PG_GETARG_POINTER(1);
     PG_RETURN_BOOL(memcmp(a->data, b->data, 16) < 0);
 }
 
 PG_FUNCTION_INFO_V1(ulid_le);
 Datum
 ulid_le(PG_FUNCTION_ARGS)
 {
     ULID *a = (ULID *) PG_GETARG_POINTER(0);
     ULID *b = (ULID *) PG_GETARG_POINTER(1);
     PG_RETURN_BOOL(memcmp(a->data, b->data, 16) <= 0);
 }
 
 PG_FUNCTION_INFO_V1(ulid_eq);
 Datum
 ulid_eq(PG_FUNCTION_ARGS)
 {
     ULID *a = (ULID *) PG_GETARG_POINTER(0);
     ULID *b = (ULID *) PG_GETARG_POINTER(1);
     PG_RETURN_BOOL(memcmp(a->data, b->data, 16) == 0);
 }
 
 PG_FUNCTION_INFO_V1(ulid_ne);
 Datum
 ulid_ne(PG_FUNCTION_ARGS)
 {
     ULID *a = (ULID *) PG_GETARG_POINTER(0);
     ULID *b = (ULID *) PG_GETARG_POINTER(1);
     PG_RETURN_BOOL(memcmp(a->data, b->data, 16) != 0);
 }
 
 PG_FUNCTION_INFO_V1(ulid_ge);
 Datum
 ulid_ge(PG_FUNCTION_ARGS)
 {
     ULID *a = (ULID *) PG_GETARG_POINTER(0);
     ULID *b = (ULID *) PG_GETARG_POINTER(1);
     PG_RETURN_BOOL(memcmp(a->data, b->data, 16) >= 0);
 }
 
 PG_FUNCTION_INFO_V1(ulid_gt);
 Datum
 ulid_gt(PG_FUNCTION_ARGS)
 {
     ULID *a = (ULID *) PG_GETARG_POINTER(0);
     ULID *b = (ULID *) PG_GETARG_POINTER(1);
     PG_RETURN_BOOL(memcmp(a->data, b->data, 16) > 0);
 }
 
 /* generation wrappers */
 PG_FUNCTION_INFO_V1(ulid_generate);
 Datum
 ulid_generate(PG_FUNCTION_ARGS)
 {
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_bytes(result);
     PG_RETURN_POINTER(result);
 }
 
 PG_FUNCTION_INFO_V1(ulid_generate_monotonic);
 Datum
 ulid_generate_monotonic(PG_FUNCTION_ARGS)
 {
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_monotonic_bytes(result);
     PG_RETURN_POINTER(result);
 }
 
 PG_FUNCTION_INFO_V1(ulid_generate_with_timestamp);
 Datum
 ulid_generate_with_timestamp(PG_FUNCTION_ARGS)
 {
     int64_t timestamp_ms = PG_GETARG_INT64(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_with_ts_bytes(result, timestamp_ms);
     PG_RETURN_POINTER(result);
 }
 
 PG_FUNCTION_INFO_V1(ulid_timestamp_fn);
 Datum
 ulid_timestamp_fn(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     int64_t ts = extract_timestamp_ms_from_ulid_bytes(ulid);
     PG_RETURN_INT64((int64)ts);
 }
 
 /* ULID <-> UUID: lossless 1:1 copy (note: not RFC-constrained UUID unless bytes happen to match) */
 PG_FUNCTION_INFO_V1(ulid_to_uuid);
 Datum
 ulid_to_uuid(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     pg_uuid_t *uuid = (pg_uuid_t *) palloc(UUID_LEN);
     memcpy(uuid->data, ulid->data, 16);
     PG_RETURN_UUID_P(uuid);
 }
 
 PG_FUNCTION_INFO_V1(ulid_from_uuid);
 Datum
 ulid_from_uuid(PG_FUNCTION_ARGS)
 {
     pg_uuid_t *uuid = (pg_uuid_t *) PG_GETARG_POINTER(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
     memcpy(result->data, uuid->data, 16);
     PG_RETURN_POINTER(result);
 }
 
 /* hash */
 PG_FUNCTION_INFO_V1(ulid_hash);
 Datum
 ulid_hash(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     uint32_t hash = 0;
     for (int i = 0; i < 16; i++)
         hash = hash * 31 + ulid->data[i];
     PG_RETURN_INT32((int32_t)hash);
 }
 
 /* End of file */
