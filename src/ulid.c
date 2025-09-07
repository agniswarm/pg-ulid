/*
 * src/ulid.c
 *
 * PostgreSQL ULID extension (single-file). Portable fixes for macOS/clang
 * (treat __int128 usage conditionally) and avoids unused static functions.
 *
 * To enable ulid-c integration: compile with -DHAVE_ULID_H and ensure
 * ulid.h is on the include path and ulid-c object/library is linked.
 *
 */

 #include "postgres.h"
 #include "fmgr.h"
 #include "utils/builtins.h"
 #include "utils/array.h"
 #include "utils/lsyscache.h"
 #include "catalog/pg_type.h"
 #include "executor/spi.h"
 #include "commands/copy.h"
 #include "access/htup_details.h"
 #include "utils/timestamp.h"
 #include "utils/uuid.h"
 #include "utils/pg_locale.h"
 #include "utils/elog.h"
 #include "libpq/pqformat.h"
 
 #include <ctype.h>
 #include <time.h>
 #include <string.h>
 #include <stdbool.h>
 #include <stdint.h>
 #include <stdlib.h>
 
 PG_MODULE_MAGIC;
 
 /* If you have ulid-c available, define HAVE_ULID_H in your CFLAGS and ensure
  * the ulid-c implementation is linked. We keep safe fallbacks if not present.
  */
 #ifdef HAVE_ULID_H
 #include <ulid.h>
 #endif
 
 /* Forward declarations of Postgres-callable functions */
 Datum ulid_in(PG_FUNCTION_ARGS);
 Datum ulid_out(PG_FUNCTION_ARGS);
 Datum ulid_send(PG_FUNCTION_ARGS);
 Datum ulid_recv(PG_FUNCTION_ARGS);
 Datum ulid_cmp(PG_FUNCTION_ARGS);
 Datum ulid_generate(PG_FUNCTION_ARGS);
 Datum ulid_generate_monotonic(PG_FUNCTION_ARGS);
 Datum ulid_generate_with_timestamp(PG_FUNCTION_ARGS);
 Datum ulid_timestamp(PG_FUNCTION_ARGS);
 Datum ulid_to_uuid(PG_FUNCTION_ARGS);
 Datum ulid_from_uuid(PG_FUNCTION_ARGS);
 Datum ulid_hash(PG_FUNCTION_ARGS);
 
 /* Boolean operator declarations */
 Datum ulid_lt(PG_FUNCTION_ARGS);
 Datum ulid_le(PG_FUNCTION_ARGS);
 Datum ulid_eq(PG_FUNCTION_ARGS);
 Datum ulid_ne(PG_FUNCTION_ARGS);
 Datum ulid_ge(PG_FUNCTION_ARGS);
 Datum ulid_gt(PG_FUNCTION_ARGS);
 
 typedef struct ULID
 {
     unsigned char data[16];
 } ULID;
 
 static const char base32_alphabet[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
 #define ULID_TEXT_LEN 26
 
 /* permissive base32 value mapping (case-insensitive, maps I/L->1, O->0) */
 static int
 base32_val(char c)
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
 
 /* Check compiler support for 128-bit integer */
 #if defined(__SIZEOF_INT128__) || defined(__GNUC__) || defined(__clang__)
 #  define HAVE_UINT128 1
 #else
 #  define HAVE_UINT128 0
 #endif
 
 /* decode canonical ULID text (25 or 26 chars) -> 16 bytes.
  * Returns true on success, false on invalid input.
  */
 static bool
 decode_ulid_text_to_bytes(const char *input, ULID *out)
 {
     if (!input || !out)
         return false;
 
     size_t len = strlen(input);
     if (!(len == 25 || len == 26))
         return false;
 
     int vals[26];
     for (size_t i = 0; i < len; i++)
     {
         int v = base32_val(input[i]);
         if (v < 0)
             return false;
         vals[i] = v & 0x1F;
     }
 
 #if HAVE_UINT128
     /* Build 128-bit accumulator */
     __uint128_t acc = 0;
     if (len == 26)
     {
         /* 26*5 = 130 bits: pack and shift right by 2 to get top 128 bits */
         for (int i = 0; i < 26; i++)
             acc = (acc << 5) | (uint64_t)vals[i];
         acc >>= 2;
     }
     else
     {
         /* 25*5 = 125 bits: shift left by 3 to pad LSBs */
         for (int i = 0; i < 25; i++)
             acc = (acc << 5) | (uint64_t)vals[i];
         acc <<= 3;
     }
 
     uint64_t high = (uint64_t)(acc >> 64);
     uint64_t low  = (uint64_t)(acc & 0xFFFFFFFFFFFFFFFFULL);
 #else
     /* Portable fallback using two 64-bit halves.
      * Represent the 128-bit accumulator as (high, low), big-endian.
      */
     uint64_t high = 0;
     uint64_t low = 0;
 
     if (len == 26)
     {
         /* Build 130-bit acc as (high130, low130) then shift right by 2 */
         /* We'll accumulate sequentially: acc = (acc << 5) | val */
         /* To shift left by 5: high = (high << 5) | (low >> 59); low = (low << 5) | val; */
         for (int i = 0; i < 26; i++)
         {
             uint32_t v = (uint32_t)vals[i] & 0x1F;
             uint64_t high_shift = (high << 5) | (low >> 59);
             uint64_t low_shift = (low << 5) | v;
             high = high_shift;
             low = low_shift;
         }
         /* now acc is 130 bits in (high, low). shift right by 2 */
         uint64_t new_low = (high << (64 - 2)) | (low >> 2);
         uint64_t new_high = high >> 2;
         high = new_high;
         low = new_low;
     }
     else
     {
         /* 25 values -> 125 bits -> left-shift by 3 to make 128 bits */
         for (int i = 0; i < 25; i++)
         {
             uint32_t v = (uint32_t)vals[i] & 0x1F;
             uint64_t high_shift = (high << 5) | (low >> 59);
             uint64_t low_shift = (low << 5) | v;
             high = high_shift;
             low = low_shift;
         }
         /* left shift by 3 */
         uint64_t new_high = (high << 3) | (low >> (64 - 3));
         uint64_t new_low = (low << 3);
         high = new_high;
         low = new_low;
     }
 #endif
 
     /* store big-endian into out->data */
     for (int i = 0; i < 8; i++)
         out->data[i] = (unsigned char)((high >> (56 - i * 8)) & 0xFF);
     for (int i = 0; i < 8; i++)
         out->data[i + 8] = (unsigned char)((low >> (56 - i * 8)) & 0xFF);
 
     return true;
 }
 
 /* encode 16 bytes -> 26-char canonical ULID text (caller provides buffer >=27) */
 static void
 encode_bytes_to_ulid_text(const ULID *in, char *out_buffer /* >=27 bytes */)
 {
     /* Build 128-bit acc from bytes (big-endian) */
 #if HAVE_UINT128
     __uint128_t acc = 0;
     for (int i = 0; i < 16; i++)
         acc = (acc << 8) | (uint64_t)in->data[i];
     /* left-shift by 2 to create 130 bits where lowest two bits are zero */
     acc <<= 2;
     /* extract 26 groups MSB-first */
     for (int i = 25; i >= 0; i--)
     {
         uint8_t v = (uint8_t)(acc & 0x1F);
         out_buffer[i] = base32_alphabet[v];
         acc >>= 5;
     }
 #else
     /* portable two-uint64 approach */
     uint64_t high = 0;
     uint64_t low = 0;
     for (int i = 0; i < 8; i++)
         high = (high << 8) | in->data[i];
     for (int i = 0; i < 8; i++)
         low = (low << 8) | in->data[8 + i];
 
     /* combine into 130-bit by left-shifting the 128-bit value by 2 */
     /* We'll extract groups from the high side MSB-first */
     /* total bits: high (64) + low (64) -> 128 bits. After shift left 2: 130 bits. */
     /* We'll extract 26 groups by repeatedly taking the top 5 bits. */
     int out_idx = 0;
     int total_groups = 26;
     /* We'll simulate a 130-bit stream by iterating group index and computing value accordingly. */
     /* Approach: for group i from 0..25, compute bit index start = 130 - 5*(i+1) */
     for (int gi = 0; gi < total_groups; gi++)
     {
         int bit_pos = (130 - 5 * (gi + 1)); /* 0-based from LSB side */
         /* We want bits [bit_pos .. bit_pos+4] (inclusive) from the 130-bit shifted-left-2 value */
         /* But since we shift-left2, that's equivalent to taking bits [bit_pos-2 .. bit_pos+2] from original 128-bit value */
         int src_high_bit = bit_pos - 2; /* 0-based LSB */
         /* We'll construct 6-byte window to cover requested bits */
         unsigned __int128 window = 0;
         /* Fill window from high & low into a 128-bit window variable */
         window = ((unsigned __int128)high << 64) | (unsigned __int128)low;
         /* shift right by src_high_bit and mask 5 bits */
         int shift_right = src_high_bit;
         unsigned int v;
         if (shift_right >= 0)
         {
             if (shift_right >= 128)
                 v = 0;
             else
                 v = (unsigned int)((window >> shift_right) & 0x1F);
         }
         else
         {
             /* negative shift (shouldn't happen), treat as 0 */
             v = 0;
         }
         out_buffer[gi] = base32_alphabet[v & 0x1F];
     }
     out_buffer[26] = '\0';
     return;
 #endif
     out_buffer[26] = '\0';
 }
 
 /* Use ulid-c for generation if available; else fallback to timestamp+rand. */
 static void
 generate_ulid_bytes(ULID *out)
 {
 #ifdef HAVE_ULID_H
     ulid_t tmp;
     ulid_make_urandom(&tmp); /* ulid-c helper */
     memcpy(out->data, tmp.b, 16);
 #else
     struct timespec ts;
     uint64_t timestamp;
 
 #if defined(CLOCK_REALTIME)
     clock_gettime(CLOCK_REALTIME, &ts);
     timestamp = (uint64_t)ts.tv_sec * 1000 + (uint64_t)(ts.tv_nsec / 1000000);
 #else
     time_t t = time(NULL);
     timestamp = (uint64_t)t * 1000;
 #endif
 
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
 
 /* Monotonic generator fallback */
 static void
 generate_ulid_monotonic_bytes(ULID *out)
 {
     static int64_t last_time_ms = 0;
     static uint32_t counter = 0;
 
     int64_t current_time_ms = (int64_t)(GetCurrentTimestamp() / 1000);
 
     if (current_time_ms > last_time_ms)
     {
         last_time_ms = current_time_ms;
         counter = 0;
     }
 
     /* write timestamp */
     out->data[0] = (last_time_ms >> 40) & 0xFF;
     out->data[1] = (last_time_ms >> 32) & 0xFF;
     out->data[2] = (last_time_ms >> 24) & 0xFF;
     out->data[3] = (last_time_ms >> 16) & 0xFF;
     out->data[4] = (last_time_ms >> 8) & 0xFF;
     out->data[5] = last_time_ms & 0xFF;
 
     counter++;
 
     out->data[6] = (counter >> 24) & 0xFF;
     out->data[7] = (counter >> 16) & 0xFF;
     out->data[8] = (counter >> 8) & 0xFF;
     out->data[9] = (counter) & 0xFF;
 
 #ifdef HAVE_ULID_H
     ulid_t tmp;
     ulid_make_urandom(&tmp);
     memcpy(&out->data[10], &tmp.b[10], 6);
 #else
     for (int i = 10; i < 16; i++)
         out->data[i] = (unsigned char)(random() & 0xFF);
 #endif
 }
 
 /* explicit ts generator */
 static void
 generate_ulid_with_ts_bytes(ULID *out, int64_t timestamp_ms)
 {
     out->data[0] = (timestamp_ms >> 40) & 0xFF;
     out->data[1] = (timestamp_ms >> 32) & 0xFF;
     out->data[2] = (timestamp_ms >> 24) & 0xFF;
     out->data[3] = (timestamp_ms >> 16) & 0xFF;
     out->data[4] = (timestamp_ms >> 8) & 0xFF;
     out->data[5] = timestamp_ms & 0xFF;
 
 #ifdef HAVE_ULID_H
     ulid_t tmp;
     ulid_make_urandom(&tmp);
     memcpy(&out->data[6], &tmp.b[6], 10);
 #else
     for (int i = 6; i < 16; i++)
         out->data[i] = (unsigned char)(random() & 0xFF);
 #endif
 }
 
 /* extract timestamp (ms) */
 static int64_t
 extract_timestamp_ms_from_ulid_bytes(const ULID *in)
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
 
 /* Postgres wrappers */
 
 /* input: text -> ulid */
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
 
 /* output: ulid -> text */
 PG_FUNCTION_INFO_V1(ulid_out);
 Datum
 ulid_out(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     char *result = (char *) palloc(ULID_TEXT_LEN + 1);
 
 #ifdef HAVE_ULID_H
     ulid_t tmp;
     memcpy(tmp.b, ulid->data, 16);
     ulid_string(&tmp, result);
 #else
     encode_bytes_to_ulid_text(ulid, result);
 #endif
 
     PG_RETURN_CSTRING(result);
 }
 
 /* binary send (bytea) */
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
 
 /* binary recv */
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
 
 /* compare */
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
 
 /* boolean operators */
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
 
 /* generate random ULID */
 PG_FUNCTION_INFO_V1(ulid_generate);
 Datum
 ulid_generate(PG_FUNCTION_ARGS)
 {
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_bytes(result);
     PG_RETURN_POINTER(result);
 }
 
 /* monotonic generate wrapper */
 PG_FUNCTION_INFO_V1(ulid_generate_monotonic);
 Datum
 ulid_generate_monotonic(PG_FUNCTION_ARGS)
 {
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_monotonic_bytes(result);
     PG_RETURN_POINTER(result);
 }
 
 /* generate with timestamp */
 PG_FUNCTION_INFO_V1(ulid_generate_with_timestamp);
 Datum
 ulid_generate_with_timestamp(PG_FUNCTION_ARGS)
 {
     int64_t timestamp_ms = PG_GETARG_INT64(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_with_ts_bytes(result, timestamp_ms);
     PG_RETURN_POINTER(result);
 }
 
 /* timestamp extraction */
 PG_FUNCTION_INFO_V1(ulid_timestamp);
 Datum
 ulid_timestamp(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     int64_t ts = extract_timestamp_ms_from_ulid_bytes(ulid);
     PG_RETURN_INT64((int64)ts);
 }
 
 /* lossless ulid <-> uuid mapping (copy bytes) */
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
 
 /* End */
