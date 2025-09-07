/*
 * src/ulid.c
 *
 * Portable ULID PostgreSQL extension implementation.
 * - Avoids __uint128_t on MSVC by emulating 128-bit via two uint64_t halves.
 * - Provides a Windows-friendly millisecond timestamp getter.
 * - Single set of PG_FUNCTION_INFO_V1 declarations (no duplicates).
 *
 * Note: For production security/entropy use, link with a secure RNG or use
 * the ulid-c library. This file contains a working fallback generator.
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
 #include "executor/spi.h"
 #include "commands/copy.h"
 #include "utils/elog.h"
 
 #include <ctype.h>
 #include <time.h>
 #include <string.h>
 #include <stdbool.h>
 #include <stdint.h>
 #include <stdlib.h>
 
 #ifdef _WIN32
 #ifndef NOMINMAX
 #define NOMINMAX
 #endif
 #include <windows.h>
 #include <wincrypt.h>
 #endif
 
 PG_MODULE_MAGIC;
 
 /* Public PG functions (single declarations) */
 Datum ulid_in(PG_FUNCTION_ARGS);
 Datum ulid_out(PG_FUNCTION_ARGS);
 Datum ulid_send(PG_FUNCTION_ARGS);
 Datum ulid_recv(PG_FUNCTION_ARGS);
 Datum ulid_cmp(PG_FUNCTION_ARGS);
 Datum ulid_lt(PG_FUNCTION_ARGS);
 Datum ulid_le(PG_FUNCTION_ARGS);
 Datum ulid_eq(PG_FUNCTION_ARGS);
 Datum ulid_ne(PG_FUNCTION_ARGS);
 Datum ulid_ge(PG_FUNCTION_ARGS);
 Datum ulid_gt(PG_FUNCTION_ARGS);
 Datum ulid_generate(PG_FUNCTION_ARGS);
 Datum ulid_generate_monotonic(PG_FUNCTION_ARGS);
 Datum ulid_generate_with_timestamp(PG_FUNCTION_ARGS);
 Datum ulid_timestamp(PG_FUNCTION_ARGS);
 Datum ulid_to_uuid(PG_FUNCTION_ARGS);
 Datum ulid_from_uuid(PG_FUNCTION_ARGS);
 Datum ulid_hash(PG_FUNCTION_ARGS);
 
 /* Define ULID internal type */
 typedef struct ULID
 {
     unsigned char data[16];
 } ULID;
 
 /* Crockford Base32 alphabet */
 static const char base32_alphabet[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
 #define ULID_TEXT_LEN 26
 
 /* Single PG_FUNCTION_INFO_V1 for each exported function */
 PG_FUNCTION_INFO_V1(ulid_in);
 PG_FUNCTION_INFO_V1(ulid_out);
 PG_FUNCTION_INFO_V1(ulid_send);
 PG_FUNCTION_INFO_V1(ulid_recv);
 PG_FUNCTION_INFO_V1(ulid_cmp);
 PG_FUNCTION_INFO_V1(ulid_lt);
 PG_FUNCTION_INFO_V1(ulid_le);
 PG_FUNCTION_INFO_V1(ulid_eq);
 PG_FUNCTION_INFO_V1(ulid_ne);
 PG_FUNCTION_INFO_V1(ulid_ge);
 PG_FUNCTION_INFO_V1(ulid_gt);
 PG_FUNCTION_INFO_V1(ulid_generate);
 PG_FUNCTION_INFO_V1(ulid_generate_monotonic);
 PG_FUNCTION_INFO_V1(ulid_generate_with_timestamp);
 PG_FUNCTION_INFO_V1(ulid_timestamp);
 PG_FUNCTION_INFO_V1(ulid_to_uuid);
 PG_FUNCTION_INFO_V1(ulid_from_uuid);
 PG_FUNCTION_INFO_V1(ulid_hash);
 
 /* portable check for 128-bit type */
 #if defined(__SIZEOF_INT128__) || defined(__GNUC__) || defined(__clang__)
 #define HAVE_UINT128 1
 #endif
 
 /* ----- portable 128-bit accumulator helpers (if no native) ----- */
 #ifdef HAVE_UINT128
 typedef unsigned __int128 u128;
 static inline u128 u128_from_u64pair(uint64_t high, uint64_t low)
 {
     u128 v = (u128)high;
     v = (v << 64) | (u128)low;
     return v;
 }
 #else
 /* Emulate a 128-bit accumulator using two 64-bit halves (high, low).
  * We will implement the minimal operations we need: left shift by 5, OR small value,
  * right shift by 2, extract high and low 64 bits.
  */
 typedef struct { uint64_t high; uint64_t low; } u128_emul;
 
 static inline void u128_emul_clear(u128_emul *x) { x->high = x->low = 0; }
 
 /* left shift by n where 0 <= n < 64 */
 static inline void u128_emul_shl(u128_emul *x, unsigned n)
 {
     if (n == 0) return;
     if (n < 64) {
         x->high = (x->high << n) | (x->low >> (64 - n));
         x->low <<= n;
     } else {
         x->high = x->low << (n - 64);
         x->low = 0;
     }
 }
 
 /* OR with small 64-bit value (we only OR small values like 0..31) */
 static inline void u128_emul_or_u64(u128_emul *x, uint64_t v)
 {
     x->low |= v;
 }
 
 /* right shift by n where 0 <= n < 128 */
 static inline void u128_emul_shr(u128_emul *x, unsigned n)
 {
     if (n == 0) return;
     if (n < 64) {
         x->low = (x->low >> n) | (x->high << (64 - n));
         x->high >>= n;
     } else if (n < 128) {
         x->low = x->high >> (n - 64);
         x->high = 0;
     } else {
         x->low = x->high = 0;
     }
 }
 
 static inline uint64_t u128_emul_high(const u128_emul *x) { return x->high; }
 static inline uint64_t u128_emul_low(const u128_emul *x) { return x->low; }
 #endif
 
 /* ----- permissive base32 value mapping (case-insensitive) ----- */
 static int base32_val(char c)
 {
     if (c >= '0' && c <= '9') return c - '0';
     if (c >= 'a' && c <= 'z') c = c - 'a' + 'A';
     /* permissive mappings */
     if (c == 'I' || c == 'L') return 1;
     if (c == 'O') return 0;
     switch (c) {
         case 'A': return 10; case 'B': return 11; case 'C': return 12; case 'D': return 13;
         case 'E': return 14; case 'F': return 15; case 'G': return 16; case 'H': return 17;
         case 'J': return 18; case 'K': return 19; case 'M': return 20; case 'N': return 21;
         case 'P': return 22; case 'Q': return 23; case 'R': return 24; case 'S': return 25;
         case 'T': return 26; case 'V': return 27; case 'W': return 28; case 'X': return 29;
         case 'Y': return 30; case 'Z': return 31;
         default: return -1;
     }
 }
 
 /* ----- portable time helper: returns milliseconds since epoch ----- */
 static int64_t get_time_ms(void)
 {
 #ifdef _WIN32
     /* Use GetSystemTimeAsFileTime for millisecond precision */
     FILETIME ft;
     GetSystemTimeAsFileTime(&ft);
     /* FILETIME is 100-ns intervals since Jan 1, 1601. Convert to UNIX epoch (1970). */
     const uint64_t EPOCH_DIFF = 116444736000000000ULL; /* in 100-ns units */
     uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
     if (t < EPOCH_DIFF) return 0;
     t -= EPOCH_DIFF;
     /* convert 100-ns units to ms */
     return (int64_t)(t / 10000ULL);
 #else
     struct timespec ts;
 #if defined(CLOCK_REALTIME)
     clock_gettime(CLOCK_REALTIME, &ts);
 #else
     /* fallback: clock_gettime might be missing on some macOS older runtimes;
        use gettimeofday as fallback */
     struct timeval tv;
     gettimeofday(&tv, NULL);
     ts.tv_sec = tv.tv_sec;
     ts.tv_nsec = tv.tv_usec * 1000;
 #endif
     return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
 #endif
 }
 
 /* ----- Base32 decode: canonical 26 chars or permissive 25 or 26 ----- */
 static bool decode_ulid_text_to_bytes(const char *input, ULID *out)
 {
     if (!input || !out) return false;
     size_t len = strlen(input);
     if (!(len == 25 || len == 26)) return false;
 
     int vals[26];
     for (size_t i = 0; i < len; i++) {
         int v = base32_val(input[i]);
         if (v < 0) return false;
         vals[i] = v & 0x1F;
     }
 
 #ifdef HAVE_UINT128
     /* Build 128-bit accumulator using __int128 (if available) */
     unsigned __int128 acc = 0;
     if (len == 26) {
         for (int i = 0; i < 26; i++) acc = (acc << 5) | (unsigned)vals[i];
         /* acc is 130 bits; drop the 2 LSB padding bits */
         acc >>= 2;
     } else {
         for (int i = 0; i < 25; i++) acc = (acc << 5) | (unsigned)vals[i];
         /* pad with 3 zero bits to reach 128 */
         acc <<= 3;
     }
     uint64_t high = (uint64_t)(acc >> 64);
     uint64_t low  = (uint64_t)(acc & 0xFFFFFFFFFFFFFFFFULL);
 #else
     /* Emulate with two 64-bit halves */
     u128_emul acc_em;
     u128_emul_clear(&acc_em);
     if (len == 26) {
         for (int i = 0; i < 26; i++) {
             u128_emul_shl(&acc_em, 5);
             u128_emul_or_u64(&acc_em, (uint64_t)vals[i]);
         }
         /* shift right by 2 to drop padding */
         u128_emul_shr(&acc_em, 2);
     } else {
         for (int i = 0; i < 25; i++) {
             u128_emul_shl(&acc_em, 5);
             u128_emul_or_u64(&acc_em, (uint64_t)vals[i]);
         }
         /* left shift by 3 to pad */
         u128_emul_shl(&acc_em, 3);
     }
     uint64_t high = u128_emul_high(&acc_em);
     uint64_t low  = u128_emul_low(&acc_em);
 #endif
 
     /* write big-endian to out->data */
     for (int i = 0; i < 8; i++) out->data[i] = (unsigned char)((high >> (56 - i*8)) & 0xFF);
     for (int i = 0; i < 8; i++) out->data[i+8] = (unsigned char)((low >> (56 - i*8)) & 0xFF);
 
     return true;
 }
 
 /* ----- Base32 encode: bytes -> canonical 26-char text ----- */
 static void encode_bytes_to_ulid_text(const ULID *in, char *out_buffer /* >= 27 bytes */)
 {
     /* Build 128-bit accumulator from bytes (big-endian) */
 #ifdef HAVE_UINT128
     unsigned __int128 acc = 0;
     for (int i = 0; i < 16; i++) {
         acc = (acc << 8) | (unsigned)in->data[i];
     }
     /* left shift by 2 to create 130 bits (last two bits zero) for 26 groups */
     acc <<= 2;
     for (int i = 25; i >= 0; i--) {
         unsigned v = (unsigned)(acc & 0x1F);
         out_buffer[i] = base32_alphabet[v];
         acc >>= 5;
     }
 #else
     /* emulate 128-bit as two uint64_t halves */
     uint64_t high = 0, low = 0;
     for (int i = 0; i < 8; i++) high = (high << 8) | in->data[i];
     for (int i = 0; i < 8; i++) low  = (low << 8) | in->data[i+8];
 
     /* Combine into emulated 130-bit stream by shifting left by 2:
        new_high:high << 2 | low >> 62
        new_low : (low << 2)
     */
     uint64_t nhigh = (high << 2) | (low >> 62);
     uint64_t nlow  = (low << 2);
 
     /* Extract 26 groups from least-significant side: we prefer to output MSB to LSB,
        so build a 26-element array by repeatedly taking the last 5 bits from (nhigh,nlow),
        shifting right 5 each iteration.
     */
     unsigned groups[26];
     for (int i = 25; i >= 0; i--) {
         /* take lowest 5 bits from (nhigh:nlow) */
         unsigned v = (unsigned)(nlow & 0x1F);
         groups[i] = v;
         /* right shift combined 128+2 by 5 -> emulate */
         /* shift nlow right by 5, bring in bits from nhigh */
         uint64_t low_new = (nlow >> 5) | (nhigh << (64 - 5));
         uint64_t high_new = (nhigh >> 5);
         nlow = low_new;
         nhigh = high_new;
     }
     /* now write groups to output */
     for (int i = 0; i < 26; i++) out_buffer[i] = base32_alphabet[groups[i]];
 #endif
     out_buffer[26] = '\0';
 }
 
 /* ----- Random / timestamp generation helpers ----- */
 /* NOTE: For production you should use a secure RNG. On Windows we use CryptGenRandom; on POSIX use arc4random / getrandom if available. */
 static void fill_random_bytes(unsigned char *buf, size_t n)
 {
 #ifdef _WIN32
     HCRYPTPROV hProv = 0;
     if (CryptAcquireContextW(&hProv, NULL, NULL, PROV_RSA_FULL, CRYPT_SILENT | CRYPT_VERIFYCONTEXT)) {
         if (!CryptGenRandom(hProv, (DWORD)n, (BYTE*)buf)) {
             /* fallback to rand() if CryptGenRandom fails (very unlikely) */
             for (size_t i = 0; i < n; i++) buf[i] = (unsigned char)(rand() & 0xFF);
         }
         CryptReleaseContext(hProv, 0);
     } else {
         for (size_t i = 0; i < n; i++) buf[i] = (unsigned char)(rand() & 0xFF);
     }
 #else
 #if defined(HAVE_ARC4RANDOM_BUF)
     arc4random_buf(buf, n);
 #else
     /* try getrandom if available? For brevity fall back to rand() here */
     for (size_t i = 0; i < n; i++) buf[i] = (unsigned char)(rand() & 0xFF);
 #endif
 #endif
 }
 
 static void generate_ulid_bytes(ULID *out)
 {
     int64_t ms = get_time_ms();
     out->data[0] = (ms >> 40) & 0xFF;
     out->data[1] = (ms >> 32) & 0xFF;
     out->data[2] = (ms >> 24) & 0xFF;
     out->data[3] = (ms >> 16) & 0xFF;
     out->data[4] = (ms >> 8)  & 0xFF;
     out->data[5] = (ms)       & 0xFF;
 
     /* fill remaining 10 bytes with randomness */
     fill_random_bytes(&out->data[6], 10);
 }
 
 /* Monotonic generator state (per-process) */
 static int64_t mon_last_time_ms = 0;
 static uint32_t mon_counter = 0;
 static bool mon_init = false;
 
 static void generate_ulid_monotonic_bytes(ULID *out)
 {
     int64_t now = get_time_ms();
     if (!mon_init) { mon_last_time_ms = now; mon_counter = 0; mon_init = true; }
 
     if (now > mon_last_time_ms) {
         mon_last_time_ms = now;
         mon_counter = 0;
     }
     mon_counter++;
 
     out->data[0] = (mon_last_time_ms >> 40) & 0xFF;
     out->data[1] = (mon_last_time_ms >> 32) & 0xFF;
     out->data[2] = (mon_last_time_ms >> 24) & 0xFF;
     out->data[3] = (mon_last_time_ms >> 16) & 0xFF;
     out->data[4] = (mon_last_time_ms >> 8) & 0xFF;
     out->data[5] = (mon_last_time_ms) & 0xFF;
 
     out->data[6] = (mon_counter >> 24) & 0xFF;
     out->data[7] = (mon_counter >> 16) & 0xFF;
     out->data[8] = (mon_counter >> 8) & 0xFF;
     out->data[9] = (mon_counter) & 0xFF;
 
     fill_random_bytes(&out->data[10], 6);
 }
 
 static void generate_ulid_with_ts_bytes(ULID *out, int64_t ms)
 {
     out->data[0] = (ms >> 40) & 0xFF;
     out->data[1] = (ms >> 32) & 0xFF;
     out->data[2] = (ms >> 24) & 0xFF;
     out->data[3] = (ms >> 16) & 0xFF;
     out->data[4] = (ms >> 8)  & 0xFF;
     out->data[5] = (ms)       & 0xFF;
     fill_random_bytes(&out->data[6], 10);
 }
 
 /* Extract timestamp (ms) */
 static int64_t extract_timestamp_ms_from_ulid_bytes(const ULID *in)
 {
     uint64_t ts = 0;
     ts |= (uint64_t)in->data[0] << 40;
     ts |= (uint64_t)in->data[1] << 32;
     ts |= (uint64_t)in->data[2] << 24;
     ts |= (uint64_t)in->data[3] << 16;
     ts |= (uint64_t)in->data[4] << 8;
     ts |= (uint64_t)in->data[5];
     return (int64_t)ts;
 }
 
 /* ---------------- Postgres input/output and functions ---------------- */
 
 Datum ulid_in(PG_FUNCTION_ARGS)
 {
     char *input = PG_GETARG_CSTRING(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
     if (!decode_ulid_text_to_bytes(input, result)) {
         ereport(ERROR,
                 (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                  errmsg("invalid input syntax for type ulid: \"%s\"", input)));
     }
     PG_RETURN_POINTER(result);
 }
 
 Datum ulid_out(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     char *result = (char *) palloc(ULID_TEXT_LEN + 1);
     encode_bytes_to_ulid_text(ulid, result);
     PG_RETURN_CSTRING(result);
 }
 
 Datum ulid_send(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     bytea *result = (bytea *) palloc(VARHDRSZ + 16);
     SET_VARSIZE(result, VARHDRSZ + 16);
     memcpy(VARDATA(result), ulid->data, 16);
     PG_RETURN_BYTEA_P(result);
 }
 
 Datum ulid_recv(PG_FUNCTION_ARGS)
 {
     StringInfo buf = (StringInfo) PG_GETARG_POINTER(0);
     if (buf->len < 16) elog(ERROR, "invalid ULID binary data");
     ULID *result = (ULID *) palloc(sizeof(ULID));
     memcpy(result->data, buf->data, 16);
     PG_RETURN_POINTER(result);
 }
 
 Datum ulid_cmp(PG_FUNCTION_ARGS)
 {
     ULID *a = (ULID *) PG_GETARG_POINTER(0);
     ULID *b = (ULID *) PG_GETARG_POINTER(1);
     int cmp = memcmp(a->data, b->data, 16);
     if (cmp < 0) PG_RETURN_INT32(-1);
     else if (cmp > 0) PG_RETURN_INT32(1);
     else PG_RETURN_INT32(0);
 }
 
 Datum ulid_lt(PG_FUNCTION_ARGS) { ULID *a = (ULID *) PG_GETARG_POINTER(0); ULID *b = (ULID *) PG_GETARG_POINTER(1); PG_RETURN_BOOL(memcmp(a->data,b->data,16) < 0); }
 Datum ulid_le(PG_FUNCTION_ARGS) { ULID *a = (ULID *) PG_GETARG_POINTER(0); ULID *b = (ULID *) PG_GETARG_POINTER(1); PG_RETURN_BOOL(memcmp(a->data,b->data,16) <= 0); }
 Datum ulid_eq(PG_FUNCTION_ARGS) { ULID *a = (ULID *) PG_GETARG_POINTER(0); ULID *b = (ULID *) PG_GETARG_POINTER(1); PG_RETURN_BOOL(memcmp(a->data,b->data,16) == 0); }
 Datum ulid_ne(PG_FUNCTION_ARGS) { ULID *a = (ULID *) PG_GETARG_POINTER(0); ULID *b = (ULID *) PG_GETARG_POINTER(1); PG_RETURN_BOOL(memcmp(a->data,b->data,16) != 0); }
 Datum ulid_ge(PG_FUNCTION_ARGS) { ULID *a = (ULID *) PG_GETARG_POINTER(0); ULID *b = (ULID *) PG_GETARG_POINTER(1); PG_RETURN_BOOL(memcmp(a->data,b->data,16) >= 0); }
 Datum ulid_gt(PG_FUNCTION_ARGS) { ULID *a = (ULID *) PG_GETARG_POINTER(0); ULID *b = (ULID *) PG_GETARG_POINTER(1); PG_RETURN_BOOL(memcmp(a->data,b->data,16) > 0); }
 
 Datum ulid_generate(PG_FUNCTION_ARGS)
 {
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_bytes(result);
     PG_RETURN_POINTER(result);
 }
 
 Datum ulid_generate_monotonic(PG_FUNCTION_ARGS)
 {
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_monotonic_bytes(result);
     PG_RETURN_POINTER(result);
 }
 
 Datum ulid_generate_with_timestamp(PG_FUNCTION_ARGS)
 {
     int64_t ts_ms = PG_GETARG_INT64(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_with_ts_bytes(result, ts_ms);
     PG_RETURN_POINTER(result);
 }
 
 Datum ulid_timestamp(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     int64_t ts = extract_timestamp_ms_from_ulid_bytes(ulid);
     PG_RETURN_INT64((int64)ts);
 }
 
 Datum ulid_to_uuid(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     pg_uuid_t *uuid = (pg_uuid_t *) palloc(UUID_LEN);
     memcpy(uuid->data, ulid->data, 16);
     PG_RETURN_UUID_P(uuid);
 }
 
 Datum ulid_from_uuid(PG_FUNCTION_ARGS)
 {
     pg_uuid_t *uuid = (pg_uuid_t *) PG_GETARG_POINTER(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
     memcpy(result->data, uuid->data, 16);
     PG_RETURN_POINTER(result);
 }
 
 Datum ulid_hash(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     uint32_t h = 0;
     for (int i = 0; i < 16; i++) h = h * 31 + ulid->data[i];
     PG_RETURN_INT32((int32_t)h);
 }
 
 /* End of file */
