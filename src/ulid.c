/*
 * src/ulid.c
 *
 * PostgreSQL ULID extension single-file implementation (cleaned, portable).
 *
 * - Single definitions only (no duplicates).
 * - Portable 128-bit helpers (uses unsigned __int128 when available).
 * - Windows clock_gettime shim.
 * - Lossless Base32 encode/decode (26-char canonical, accepts 25/26 permissive).
 *
 * Build: normal PGXS Makefile. On Windows with MSVC you may need to set
 * appropriate include paths and link settings (see your Makefile.win).
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
 
 /* ----------------------- Portability helpers -------------------------
    Provide a u128 abstraction (builtin unsigned __int128 when available,
    otherwise a minimal struct) and a clock_gettime shim for Windows.
 --------------------------------------------------------------------- */
 
 #if defined(__SIZEOF_INT128__) || defined(__GNUC__) || defined(__clang__)
 typedef unsigned __int128 u128;
 static inline u128 u128_from_u64pair(uint64_t high, uint64_t low)
 {
     u128 x = (u128)high;
     x = (x << 64) | (u128)low;
     return x;
 }
 static inline void u128_to_u64pair(u128 a, uint64_t *high, uint64_t *low)
 {
     *high = (uint64_t)(a >> 64);
     *low  = (uint64_t)a;
 }
 static inline u128 u128_shl(u128 a, unsigned n) { return a << n; }
 static inline u128 u128_shr(u128 a, unsigned n) { return a >> n; }
 static inline u128 u128_or(u128 a, u128 b) { return a | b; }
 #else
 typedef struct { uint64_t hi; uint64_t lo; } u128;
 static inline u128 u128_from_u64pair(uint64_t high, uint64_t low) { u128 r = {high, low}; return r; }
 static inline void u128_to_u64pair(u128 a, uint64_t *high, uint64_t *low) { *high = a.hi; *low = a.lo; }
 static inline u128 u128_or(u128 a, u128 b) { u128 r = {a.hi | b.hi, a.lo | b.lo}; return r; }
 static inline u128 u128_shl(u128 a, unsigned n)
 {
     u128 out = {0,0};
     if (n == 0) return a;
     if (n < 64) {
         out.hi = (a.hi << n) | (a.lo >> (64 - n));
         out.lo = (a.lo << n);
     } else if (n < 128) {
         out.hi = (a.lo << (n - 64));
         out.lo = 0;
     }
     return out;
 }
 static inline u128 u128_shr(u128 a, unsigned n)
 {
     u128 out = {0,0};
     if (n == 0) return a;
     if (n < 64) {
         out.lo = (a.lo >> n) | (a.hi << (64 - n));
         out.hi = (a.hi >> n);
     } else if (n < 128) {
         out.lo = (a.hi >> (n - 64));
         out.hi = 0;
     }
     return out;
 }
 #endif
 
 /* helper: acc = (acc << 5) | (v5 & 0x1F) */
 static inline u128 u128_lshift_or_small(u128 acc, unsigned v5)
 {
 #if defined(__SIZEOF_INT128__) || defined(__GNUC__) || defined(__clang__)
     acc = u128_shl(acc, 5);
     acc = u128_or(acc, (u128)(v5 & 0x1F));
     return acc;
 #else
     u128 small = u128_from_u64pair(0, (uint64_t)(v5 & 0x1F));
     u128 shifted = u128_shl(acc, 5);
     return u128_or(shifted, small);
 #endif
 }
 
 /* Windows clock_gettime shim (if needed) */
 #if defined(_WIN32) && !defined(__MINGW32__)
 #include <windows.h>
 #ifndef CLOCK_REALTIME
 #define CLOCK_REALTIME 0
 #endif
 static int clock_gettime_win(int clk_id, struct timespec *ts)
 {
     (void)clk_id;
     FILETIME ft;
     HMODULE h = GetModuleHandleW(L"Kernel32.dll");
     if (h) {
         typedef VOID (WINAPI *GSPAFT)(LPFILETIME);
         GSPAFT p = (GSPAFT)GetProcAddress(h, "GetSystemTimePreciseAsFileTime");
         if (p) {
             p(&ft);
         } else {
             GetSystemTimeAsFileTime(&ft);
         }
     } else {
         GetSystemTimeAsFileTime(&ft);
     }
     unsigned long long v = (((unsigned long long)ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
     const unsigned long long EPOCH_DIFF = 11644473600ULL;
     unsigned long long usec = (v / 10ULL) - (EPOCH_DIFF * 1000000ULL);
     ts->tv_sec  = (time_t)(usec / 1000000ULL);
     ts->tv_nsec = (long)((usec % 1000000ULL) * 1000ULL);
     return 0;
 }
 static int clock_gettime(int clk_id, struct timespec *ts) { return clock_gettime_win(clk_id, ts); }
 #endif
 
 /* ----------------------- ULID implementation ------------------------- */
 
 /* ULID internal representation */
 typedef struct ULID { unsigned char data[16]; } ULID;
 
 /* Crockford base32 canonical alphabet (26 chars) */
 static const char base32_alphabet[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
 #define ULID_TEXT_LEN 26
 
 /* permissive base32 value mapping */
 static int base32_val(char c)
 {
     if (c >= '0' && c <= '9') return c - '0';
     if (c >= 'a' && c <= 'z') c = c - 'a' + 'A';
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
 
 /* Decode text (25 or 26 chars) into 16 bytes (ULID). Returns true on success. */
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
 
     u128 acc = u128_from_u64pair(0,0);
 
     if (len == 26) {
         /* 26*5 = 130 bits, drop the lowest 2 bits after accumulation */
         for (int i = 0; i < 26; i++) acc = u128_lshift_or_small(acc, vals[i]);
         /* acc now contains 130-bit value in big-endian. Shift right by 2 to get 128-bit ULID */
 #if defined(__SIZEOF_INT128__) || defined(__GNUC__) || defined(__clang__)
         acc = u128_shr(acc, 2);
         uint64_t high = (uint64_t)(acc >> 64);
         uint64_t low = (uint64_t)acc;
 #else
         acc = u128_shr(acc, 2);
         uint64_t high, low;
         u128_to_u64pair(acc, &high, &low);
 #endif
         uint64_t high_u64, low_u64;
         u128_to_u64pair(acc, &high_u64, &low_u64);
         for (int i = 0; i < 8; i++) out->data[i] = (unsigned char)((high_u64 >> (56 - i*8)) & 0xFF);
         for (int i = 0; i < 8; i++) out->data[i+8] = (unsigned char)((low_u64 >> (56 - i*8)) & 0xFF);
     } else {
         /* 25*5 = 125 bits; shift left by 3 to make 128 bits */
         for (int i = 0; i < 25; i++) acc = u128_lshift_or_small(acc, vals[i]);
         acc = u128_shl(acc, 3); /* pad 3 zero bits on the right */
         uint64_t high_u64, low_u64;
         u128_to_u64pair(acc, &high_u64, &low_u64);
         for (int i = 0; i < 8; i++) out->data[i] = (unsigned char)((high_u64 >> (56 - i*8)) & 0xFF);
         for (int i = 0; i < 8; i++) out->data[i+8] = (unsigned char)((low_u64 >> (56 - i*8)) & 0xFF);
     }
     return true;
 }
 
 /* Encode 16 bytes -> 26-char canonical ULID text into out_buffer (>=27 bytes) */
 static void encode_bytes_to_ulid_text(const ULID *in, char *out_buffer)
 {
     /* Build 128-bit big-endian integer then left-shift by 2 to make 130 bits */
     u128 acc = u128_from_u64pair(0,0);
 #if defined(__SIZEOF_INT128__) || defined(__GNUC__) || defined(__clang__)
     for (int i = 0; i < 16; i++) {
         acc = u128_shl(acc, 8);
         acc = u128_or(acc, (u128)in->data[i]);
     }
     acc = u128_shl(acc, 2); /* produce 130 bits, low 2 bits zero */
     for (int i = 25; i >= 0; i--) {
         unsigned v = (unsigned)(acc & (u128)0x1F);
         out_buffer[i] = base32_alphabet[v];
         acc = u128_shr(acc, 5);
     }
 #else
     /* Build using the struct implementation */
     u128 tmp = u128_from_u64pair(0,0);
     for (int i = 0; i < 16; i++) {
         /* shift left by 8 and OR next byte */
         tmp = u128_shl(tmp, 8);
         u128 b = u128_from_u64pair(0, in->data[i]);
         tmp = u128_or(tmp, b);
     }
     tmp = u128_shl(tmp, 2);
     for (int i = 25; i >= 0; i--) {
         uint64_t hi, lo;
         u128_to_u64pair(tmp, &hi, &lo);
         unsigned v = (unsigned)(lo & 0x1F);
         out_buffer[i] = base32_alphabet[v];
         tmp = u128_shr(tmp, 5);
     }
 #endif
     out_buffer[26] = '\0';
 }
 
 /* Generate ULID bytes: prefer GetCurrentTimestamp() to align with Postgres time semantics */
 static void generate_ulid_bytes(ULID *out)
 {
     struct timespec ts;
 #if defined(_WIN32) && !defined(__MINGW32__)
     clock_gettime(CLOCK_REALTIME, &ts); /* shim */
 #else
     clock_gettime(CLOCK_REALTIME, &ts);
 #endif
     uint64_t timestamp = (uint64_t)ts.tv_sec * 1000 + (uint64_t)(ts.tv_nsec / 1000000);
     out->data[0] = (timestamp >> 40) & 0xFF;
     out->data[1] = (timestamp >> 32) & 0xFF;
     out->data[2] = (timestamp >> 24) & 0xFF;
     out->data[3] = (timestamp >> 16) & 0xFF;
     out->data[4] = (timestamp >> 8) & 0xFF;
     out->data[5] = timestamp & 0xFF;
     for (int i = 6; i < 16; i++) out->data[i] = (unsigned char)(random() & 0xFF);
 }
 
 /* Monotonic generator: maintains counter per-process and resets when ms advances */
 static void generate_ulid_monotonic_bytes(ULID *out)
 {
     static int64_t last_time_ms = 0;
     static uint32_t counter = 0;
     int64_t current_time_ms = (int64_t)(GetCurrentTimestamp() / 1000);
 
     if (current_time_ms > last_time_ms) {
         last_time_ms = current_time_ms;
         counter = 0;
     }
     /* fill timestamp */
     out->data[0] = (last_time_ms >> 40) & 0xFF;
     out->data[1] = (last_time_ms >> 32) & 0xFF;
     out->data[2] = (last_time_ms >> 24) & 0xFF;
     out->data[3] = (last_time_ms >> 16) & 0xFF;
     out->data[4] = (last_time_ms >> 8) & 0xFF;
     out->data[5] = last_time_ms & 0xFF;
     /* monotonic counter in bytes 6..9 */
     counter++;
     out->data[6] = (counter >> 24) & 0xFF;
     out->data[7] = (counter >> 16) & 0xFF;
     out->data[8] = (counter >> 8) & 0xFF;
     out->data[9] = (counter) & 0xFF;
     for (int i = 10; i < 16; i++) out->data[i] = (unsigned char)(random() & 0xFF);
 }
 
 /* Generate ULID with explicit timestamp (ms) */
 static void generate_ulid_with_ts_bytes(ULID *out, int64_t timestamp_ms)
 {
     out->data[0] = (timestamp_ms >> 40) & 0xFF;
     out->data[1] = (timestamp_ms >> 32) & 0xFF;
     out->data[2] = (timestamp_ms >> 24) & 0xFF;
     out->data[3] = (timestamp_ms >> 16) & 0xFF;
     out->data[4] = (timestamp_ms >> 8) & 0xFF;
     out->data[5] = (timestamp_ms) & 0xFF;
     for (int i = 6; i < 16; i++) out->data[i] = (unsigned char)(random() & 0xFF);
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
 
 /* ----------------------- PostgreSQL exports ------------------------- */
 
 /* forward declarations (single set) */
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
 
 /* Input function: text -> ulid */
 PG_FUNCTION_INFO_V1(ulid_in);
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
 
 /* Output function: ulid -> text */
 PG_FUNCTION_INFO_V1(ulid_out);
 Datum ulid_out(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     char *result = (char *) palloc(ULID_TEXT_LEN + 1);
     encode_bytes_to_ulid_text(ulid, result);
     PG_RETURN_CSTRING(result);
 }
 
 /* Binary send: produce 16-byte bytea */
 PG_FUNCTION_INFO_V1(ulid_send);
 Datum ulid_send(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     bytea *result = (bytea *) palloc(VARHDRSZ + 16);
     SET_VARSIZE(result, VARHDRSZ + 16);
     memcpy(VARDATA(result), ulid->data, 16);
     PG_RETURN_BYTEA_P(result);
 }
 
 /* Binary receive */
 PG_FUNCTION_INFO_V1(ulid_recv);
 Datum ulid_recv(PG_FUNCTION_ARGS)
 {
     StringInfo buf = (StringInfo) PG_GETARG_POINTER(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
     if (buf->len < 16)
         elog(ERROR, "invalid ULID binary data");
     memcpy(result->data, buf->data, 16);
     PG_RETURN_POINTER(result);
 }
 
 /* Comparison (memcmp of 16 bytes) */
 PG_FUNCTION_INFO_V1(ulid_cmp);
 Datum ulid_cmp(PG_FUNCTION_ARGS)
 {
     ULID *a = (ULID *) PG_GETARG_POINTER(0);
     ULID *b = (ULID *) PG_GETARG_POINTER(1);
     int cmp = memcmp(a->data, b->data, 16);
     if (cmp < 0) PG_RETURN_INT32(-1);
     else if (cmp > 0) PG_RETURN_INT32(1);
     else PG_RETURN_INT32(0);
 }
 
 /* Boolean operators */
 PG_FUNCTION_INFO_V1(ulid_lt);
 Datum ulid_lt(PG_FUNCTION_ARGS) { ULID *a=(ULID*)PG_GETARG_POINTER(0); ULID *b=(ULID*)PG_GETARG_POINTER(1); PG_RETURN_BOOL(memcmp(a->data,b->data,16) < 0); }
 PG_FUNCTION_INFO_V1(ulid_le);
 Datum ulid_le(PG_FUNCTION_ARGS) { ULID *a=(ULID*)PG_GETARG_POINTER(0); ULID *b=(ULID*)PG_GETARG_POINTER(1); PG_RETURN_BOOL(memcmp(a->data,b->data,16) <= 0); }
 PG_FUNCTION_INFO_V1(ulid_eq);
 Datum ulid_eq(PG_FUNCTION_ARGS) { ULID *a=(ULID*)PG_GETARG_POINTER(0); ULID *b=(ULID*)PG_GETARG_POINTER(1); PG_RETURN_BOOL(memcmp(a->data,b->data,16) == 0); }
 PG_FUNCTION_INFO_V1(ulid_ne);
 Datum ulid_ne(PG_FUNCTION_ARGS) { ULID *a=(ULID*)PG_GETARG_POINTER(0); ULID *b=(ULID*)PG_GETARG_POINTER(1); PG_RETURN_BOOL(memcmp(a->data,b->data,16) != 0); }
 PG_FUNCTION_INFO_V1(ulid_ge);
 Datum ulid_ge(PG_FUNCTION_ARGS) { ULID *a=(ULID*)PG_GETARG_POINTER(0); ULID *b=(ULID*)PG_GETARG_POINTER(1); PG_RETURN_BOOL(memcmp(a->data,b->data,16) >= 0); }
 PG_FUNCTION_INFO_V1(ulid_gt);
 Datum ulid_gt(PG_FUNCTION_ARGS) { ULID *a=(ULID*)PG_GETARG_POINTER(0); ULID *b=(ULID*)PG_GETARG_POINTER(1); PG_RETURN_BOOL(memcmp(a->data,b->data,16) > 0); }
 
 /* Random ULID generator (ulid()) */
 PG_FUNCTION_INFO_V1(ulid_generate);
 Datum ulid_generate(PG_FUNCTION_ARGS)
 {
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_bytes(result);
     PG_RETURN_POINTER(result);
 }
 
 /* Monotonic generator wrapper (ulid_generate_monotonic) */
 PG_FUNCTION_INFO_V1(ulid_generate_monotonic);
 Datum ulid_generate_monotonic(PG_FUNCTION_ARGS)
 {
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_monotonic_bytes(result);
     PG_RETURN_POINTER(result);
 }
 
 /* Generator with explicit timestamp (ms) */
 PG_FUNCTION_INFO_V1(ulid_generate_with_timestamp);
 Datum ulid_generate_with_timestamp(PG_FUNCTION_ARGS)
 {
     int64_t timestamp_ms = PG_GETARG_INT64(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
     generate_ulid_with_ts_bytes(result, timestamp_ms);
     PG_RETURN_POINTER(result);
 }
 
 /* Extract timestamp (ms) from ULID */
 PG_FUNCTION_INFO_V1(ulid_timestamp);
 Datum ulid_timestamp(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     int64_t ts = extract_timestamp_ms_from_ulid_bytes(ulid);
     PG_RETURN_INT64((int64)ts);
 }
 
 /* ULID <-> UUID mapping: lossless 1:1 byte copy (note: UUID won't be RFC-4122 conforming) */
 PG_FUNCTION_INFO_V1(ulid_to_uuid);
 Datum ulid_to_uuid(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     pg_uuid_t *uuid = (pg_uuid_t *) palloc(UUID_LEN);
     memcpy(uuid->data, ulid->data, 16);
     PG_RETURN_UUID_P(uuid);
 }
 
 PG_FUNCTION_INFO_V1(ulid_from_uuid);
 Datum ulid_from_uuid(PG_FUNCTION_ARGS)
 {
     pg_uuid_t *uuid = (pg_uuid_t *) PG_GETARG_POINTER(0);
     ULID *result = (ULID *) palloc(sizeof(ULID));
     memcpy(result->data, uuid->data, 16);
     PG_RETURN_POINTER(result);
 }
 
 /* Hash */
 PG_FUNCTION_INFO_V1(ulid_hash);
 Datum ulid_hash(PG_FUNCTION_ARGS)
 {
     ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
     uint32_t hash = 0;
     for (int i = 0; i < 16; i++) hash = hash * 31 + ulid->data[i];
     PG_RETURN_INT32((int32_t)hash);
 }
 
 /* end of file */
