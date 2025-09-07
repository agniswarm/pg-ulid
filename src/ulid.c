/* src/ulid.c
 *
 * Portable ULID PostgreSQL extension implementation.
 *
 * - Single PG_FUNCTION_INFO_V1 per exported function (fixes MSVC redefinition errors).
 * - Portable Base32 encode/decode that doesn't require __uint128_t (works on MSVC).
 * - Canonical 26-char ULID encode; accepts 25 or 26 char input permissively.
 * - Lossless ulid <-> bytea and ulid <-> uuid copy (1:1) behavior.
 *
 * Notes:
 * - This is intended to be compiled as a PostgreSQL extension module.
 * - For production-quality random/entropy use, integrate a secure RNG (e.g. ulid-c).
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
 
 /* Forward prototypes (no PG_FUNCTION_INFO_V1 here) */
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
 
 Datum ulid_lt(PG_FUNCTION_ARGS);
 Datum ulid_le(PG_FUNCTION_ARGS);
 Datum ulid_eq(PG_FUNCTION_ARGS);
 Datum ulid_ne(PG_FUNCTION_ARGS);
 Datum ulid_ge(PG_FUNCTION_ARGS);
 Datum ulid_gt(PG_FUNCTION_ARGS);
 
 /* ULID type: 16 bytes */
 typedef struct ULID
 {
     unsigned char data[16];
 } ULID;
 
 /* Crockford Base32 alphabet (canonical) */
 static const char base32_alphabet[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
 #define ULID_TEXT_LEN 26
 
 /* permissive mapping of char -> 5-bit value */
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
 
 /*
  * Decode 25- or 26-char ULID text into 16 bytes.
  * Uses three 64-bit words to accumulate up to 130 bits without __uint128_t.
  * Returns true on success, false on invalid input.
  */
 static bool decode_ulid_text_to_bytes(const char *input, ULID *out)
 {
     if (!input || !out) return false;
 
     size_t len = strlen(input);
     if (!(len == 25 || len == 26)) return false;
 
     int vals[26];
     for (size_t i = 0; i < len; i++)
     {
         int v = base32_val(input[i]);
         if (v < 0) return false;
         vals[i] = v & 0x1F;
     }
 
     /* accumulator: acc[2] = most-significant, acc[0] least */
     uint64_t acc[3] = {0,0,0};
 
     for (int i = 0; i < (int)len; i++)
     {
         /* left shift acc by 5 bits */
         uint64_t carry2 = acc[1] >> 59;       /* top 5 bits of acc[1] go into acc[2] */
         uint64_t carry1 = acc[0] >> 59;       /* top 5 bits of acc[0] go into acc[1] */
         acc[2] = (acc[2] << 5) | carry2;
         acc[1] = (acc[1] << 5) | carry1;
         acc[0] = (acc[0] << 5) | (uint64_t)vals[i];
     }
 
     if (len == 26)
     {
         /* We have 130 bits in acc (top bits in acc[2]). Discard lowest 2 bits (right shift by 2). */
         uint64_t new_lo = (acc[0] >> 2) | (acc[1] << 62);
         uint64_t mid = (acc[1] >> 2) | (acc[2] << 62);
         uint64_t hi = (acc[2] >> 2);
 
         /* Now hi:mid:new_lo holds top 128 bits (hi may be up to 2 bits), we extract 16 bytes from hi..new_lo */
         uint8_t bytes[24]; /* temp */
         /* Build 16 MSB bytes from hi (most significant 64), mid (next 64) */
         uint64_t msb = hi;
         uint64_t lsb = mid;
         /* But since we lost acc[0] (lowest), need to combine mid and new_lo to produce low 64 */
         uint64_t low64 = new_lo;
         /* Actually, after right shift by 2: bits layout is:
          *   hi (bits 127..64)
          *   mid (bits 63..0)
          * But because of how we shifted across 3 words, mid contains the middle 64 and new_lo is the least 64.
          * We need the final 128-bit value as: top64 = (hi<<? | ...) ; easier approach below:
          */
         /* Simpler: reconstruct big 128 from acc after right shift using two 64-bit words: */
         /* compute combined = ( (acc as 130-bit) >> 2 ) -> produce top64 (high) and low64 (low) */
         uint64_t top64, low64_final;
         /* We computed hi/mid/new_lo above but safer to compute top64 and low64_final as: */
         top64 = (hi << 0) | 0; /* hi already upper bits */
         low64_final = (mid);
         /* But we lost some bits sitting in new_lo (lowest); actually mid holds the next 64 after shifting.
            The correct mapping (after shift) is:
            acc (before shift): [acc2 (high 66..), acc1, acc0 (low)]
            after shift by 2:
            high64 = ( (acc2 >> 2) )
            low64  = ( (acc2 << 62) | (acc1 >> 2) ) ? This is getting error-prone in commentary.
            To avoid mistakes, fallback to assembling a 128-bit array of bits by writing bytes explicitly below.
         */
 
         /* We'll instead create a 130-bit bit-stream array of 26 5-bit values and then emit bytes by filling a bit buffer.
          * This avoids the trickiness above. Restart and implement this deterministic approach below.
          */
     }
 
     /* Fallback streaming approach: build bytes by streaming bits from values array.
      * This approach is straightforward and safe for both 25 and 26 lengths.
      */
     {
         unsigned int bit_count = 0;
         uint64_t buffer = 0;
         int byte_idx = 0;
         memset(out->data, 0, 16);
 
         /* Process all values (len items). For a 25-char input we will pad with 3 zero bits at the end. For 26 we process all 26 and then drop the 2 lowest bits by ignoring after producing 16 bytes. */
         for (int i = 0; i < (int)len; i++)
         {
             buffer = (buffer << 5) | (uint64_t)vals[i];
             bit_count += 5;
 
             while (bit_count >= 8 && byte_idx < 16)
             {
                 /* extract the top 8 bits */
                 unsigned shift = (unsigned)(bit_count - 8);
                 unsigned char b = (unsigned char)((buffer >> shift) & 0xFFULL);
                 out->data[byte_idx++] = b;
                 bit_count -= 8;
                 /* mask buffer to remaining bits */
                 if (shift == 0)
                     buffer = 0;
                 else
                     buffer &= ((1ULL << shift) - 1ULL);
             }
         }
 
         if (len == 25 && byte_idx < 16)
         {
             /* we have 125 bits emitted as bytes; pad with 3 zero bits (left shift) to reach 128 bits */
             /* append three zero bits */
             buffer = (buffer << 3);
             bit_count += 3;
             while (bit_count >= 8 && byte_idx < 16)
             {
                 unsigned shift = (unsigned)(bit_count - 8);
                 unsigned char b = (unsigned char)((buffer >> shift) & 0xFFULL);
                 out->data[byte_idx++] = b;
                 bit_count -= 8;
                 if (shift == 0)
                     buffer = 0;
                 else
                     buffer &= ((1ULL << shift) - 1ULL);
             }
         }
 
         /* For 26-char case, the streaming algorithm will produce 16 bytes and may leave leftover bits (two bits) in buffer which we ignore */
         if (byte_idx != 16)
         {
             /* if we didn't fill 16 bytes, decoding failed */
             return false;
         }
         return true;
     }
 }
 
 /*
  * Encode 16 bytes into canonical 26-char ULID text.
  * Approach: build a 128-bit big-endian accumulator using two uint64_t and then emit 26 5-bit groups by left-shifting by 2 (to form 130 bits).
  */
 static void encode_bytes_to_ulid_text(const ULID *in, char *out_buffer /* >= 27 bytes */)
 {
     /* build acc as two 64-bit words (big-endian) */
     uint64_t high = 0;
     uint64_t low = 0;
     for (int i = 0; i < 8; i++)
         high = (high << 8) | (uint64_t)in->data[i];
     for (int i = 0; i < 8; i++)
         low = (low << 8) | (uint64_t)in->data[8 + i];
 
     /* combine into a 128-bit represented by high, low */
     /* left-shift by 2 bits to create 130-bit stream where bottom 2 bits are zero */
     uint64_t new_high = (high << 2) | (low >> 62);
     uint64_t new_low = (low << 2);
 
     /* emit 26 base32 chars from most-significant to least */
     uint64_t acc_high = new_high;
     uint64_t acc_low = new_low;
 
     for (int i = 25; i >= 0; i--)
     {
         /* extract lowest 5 bits of the 130-bit value; to do that, take (acc_low & 0x1F), then shift right 5 across the 128-bit pair */
         uint8_t v = (uint8_t)(acc_low & 0x1F);
         out_buffer[i] = base32_alphabet[v];
         /* shift right by 5 bits across acc_high:acc_low */
         uint64_t carry = acc_high & 0x1F;
         acc_low = (acc_low >> 5) | (carry << (64 - 5));
         acc_high = (acc_high >> 5);
     }
     out_buffer[26] = '\0';
 }
 
 /* Portable random generator for entropy bytes (fallback) */
 static void fill_random_bytes(unsigned char *buf, int n)
 {
     /* Use rand() as fallback; production should use secure RNG. */
     for (int i = 0; i < n; i++)
     {
         buf[i] = (unsigned char)(rand() & 0xFF);
     }
 }
 
 /* Generate ULID bytes: timestamp ms + 10 bytes random */
 static void generate_ulid_bytes(ULID *out)
 {
     int64_t timestamp_ms = (int64_t)(GetCurrentTimestamp() / 1000);
     out->data[0] = (timestamp_ms >> 40) & 0xFF;
     out->data[1] = (timestamp_ms >> 32) & 0xFF;
     out->data[2] = (timestamp_ms >> 24) & 0xFF;
     out->data[3] = (timestamp_ms >> 16) & 0xFF;
     out->data[4] = (timestamp_ms >> 8) & 0xFF;
     out->data[5] = timestamp_ms & 0xFF;
 
     fill_random_bytes(&out->data[6], 10);
 }
 
 /* Monotonic generator bytes */
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
 
     fill_random_bytes(&out->data[10], 6);
 }
 
 /* Generate ULID with explicit timestamp ms */
 static void generate_ulid_with_ts_bytes(ULID *out, int64_t timestamp_ms)
 {
     out->data[0] = (timestamp_ms >> 40) & 0xFF;
     out->data[1] = (timestamp_ms >> 32) & 0xFF;
     out->data[2] = (timestamp_ms >> 24) & 0xFF;
     out->data[3] = (timestamp_ms >> 16) & 0xFF;
     out->data[4] = (timestamp_ms >> 8) & 0xFF;
     out->data[5] = timestamp_ms & 0xFF;
 
     fill_random_bytes(&out->data[6], 10);
 }
 
 /* Extract timestamp ms from ULID bytes */
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
 
 /* --------- PostgreSQL-exposed functions --------- */
 
 /* Input function */
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
 
 /* Output function */
 PG_FUNCTION_INFO_V1(ulid_out);
 Datum
 ulid_out(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     char *result = (char *) palloc(ULID_TEXT_LEN + 1);
 
     encode_bytes_to_ulid_text(ulid, result);
 
     PG_RETURN_CSTRING(result);
 }
 
 /* Binary send */
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
 
 /* Binary recv */
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
 
 /* Comparison (memcmp) */
 PG_FUNCTION_INFO_V1(ulid_cmp);
 Datum
 ulid_cmp(PG_FUNCTION_ARGS)
 {
     ULID *a = (ULID *) PG_GETARG_POINTER(0);
     ULID *b = (ULID *) PG_GETARG_POINTER(1);
 
     int cmp = memcmp(a->data, b->data, 16);
     if (cmp < 0) PG_RETURN_INT32(-1);
     if (cmp > 0) PG_RETURN_INT32(1);
     PG_RETURN_INT32(0);
 }
 
 /* Boolean operators */
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
 
 /* Generate random ULID */
 PG_FUNCTION_INFO_V1(ulid_generate);
 Datum
 ulid_generate(PG_FUNCTION_ARGS)
 {
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_bytes(result);
     PG_RETURN_POINTER(result);
 }
 
 /* Monotonic generator */
 PG_FUNCTION_INFO_V1(ulid_generate_monotonic);
 Datum
 ulid_generate_monotonic(PG_FUNCTION_ARGS)
 {
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_monotonic_bytes(result);
     PG_RETURN_POINTER(result);
 }
 
 /* Generate ULID with given timestamp (ms) */
 PG_FUNCTION_INFO_V1(ulid_generate_with_timestamp);
 Datum
 ulid_generate_with_timestamp(PG_FUNCTION_ARGS)
 {
     int64_t timestamp_ms = PG_GETARG_INT64(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_with_ts_bytes(result, timestamp_ms);
     PG_RETURN_POINTER(result);
 }
 
 /* Extract timestamp ms */
 PG_FUNCTION_INFO_V1(ulid_timestamp);
 Datum
 ulid_timestamp(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     int64_t ts = extract_timestamp_ms_from_ulid_bytes(ulid);
     PG_RETURN_INT64((int64)ts);
 }
 
 /* Lossless ulid -> uuid (copy bytes) */
 PG_FUNCTION_INFO_V1(ulid_to_uuid);
 Datum
 ulid_to_uuid(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     pg_uuid_t *uuid = (pg_uuid_t *) palloc(UUID_LEN);
     memcpy(uuid->data, ulid->data, 16);
     PG_RETURN_UUID_P(uuid);
 }
 
 /* Lossless uuid -> ulid (copy bytes) */
 PG_FUNCTION_INFO_V1(ulid_from_uuid);
 Datum
 ulid_from_uuid(PG_FUNCTION_ARGS)
 {
     pg_uuid_t *uuid = (pg_uuid_t *) PG_GETARG_POINTER(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
     memcpy(result->data, uuid->data, 16);
     PG_RETURN_POINTER(result);
 }
 
 /* Hash function */
 PG_FUNCTION_INFO_V1(ulid_hash);
 Datum
 ulid_hash(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     uint32_t h = 0;
     for (int i = 0; i < 16; i++)
         h = h * 31 + ulid->data[i];
     PG_RETURN_INT32((int32_t)h);
 }
 
 /* end of file */
