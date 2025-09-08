/* src/ulid.c
 *
 * C90-compatible, portable ULID PostgreSQL extension implementation.
 * - Move declarations to top of blocks to satisfy -Wdeclaration-after-statement
 * - Avoid unused variables
 * - Portable time and RNG
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

#ifdef _WIN32
#include <Windows.h>
#include <wincrypt.h>
#endif

PG_MODULE_MAGIC;

/* forward declarations removed - using PG_FUNCTION_INFO_V1 instead */

typedef struct ULID
{
    unsigned char data[16];
} ULID;

static const char base32_alphabet[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
#define ULID_TEXT_LEN 26

/* Portable 128-bit accumulator support */
#if defined(__SIZEOF_INT128__) || defined(__GNUC__) || defined(__clang__)
typedef __uint128_t u128;
#define HAVE_U128 1
#else
typedef struct
{
    uint64_t hi;
    uint64_t lo;
} u128;
#define HAVE_U128 0
#endif

/* base32 value (permissive) */
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
    case 'A':
        return 10;
    case 'B':
        return 11;
    case 'C':
        return 12;
    case 'D':
        return 13;
    case 'E':
        return 14;
    case 'F':
        return 15;
    case 'G':
        return 16;
    case 'H':
        return 17;
    case 'J':
        return 18;
    case 'K':
        return 19;
    case 'M':
        return 20;
    case 'N':
        return 21;
    case 'P':
        return 22;
    case 'Q':
        return 23;
    case 'R':
        return 24;
    case 'S':
        return 25;
    case 'T':
        return 26;
    case 'V':
        return 27;
    case 'W':
        return 28;
    case 'X':
        return 29;
    case 'Y':
        return 30;
    case 'Z':
        return 31;
    default:
        return -1;
    }
}

/* Helpers for u128 fallback */
#if !HAVE_U128
static u128 u128_zero(void)
{
    u128 r;
    r.hi = 0;
    r.lo = 0;
    return r;
}
static u128 u128_shl(u128 a, unsigned int s)
{
    u128 r;
    if (s == 0)
    {
        r.hi = a.hi;
        r.lo = a.lo;
        return r;
    }
    if (s < 64)
    {
        r.hi = (a.hi << s) | (a.lo >> (64 - s));
        r.lo = a.lo << s;
    }
    else if (s < 128)
    {
        r.hi = a.lo << (s - 64);
        r.lo = 0;
    }
    else
    {
        r.hi = 0;
        r.lo = 0;
    }
    return r;
}
static u128 u128_or_u64(u128 a, uint64_t v)
{
    a.lo |= v;
    return a;
}
static u128 u128_lshift_add(u128 a, uint64_t v)
{ /* a = (a << 5) | v */
    a = u128_shl(a, 5);
    a.lo |= (v & 0x1F);
    return a;
}
static u128 u128_rshift(u128 a, unsigned int s)
{
    u128 r;
    if (s == 0)
    {
        r.hi = a.hi;
        r.lo = a.lo;
        return r;
    }
    if (s < 64)
    {
        r.lo = (a.lo >> s) | (a.hi << (64 - s));
        r.hi = (a.hi >> s);
    }
    else if (s < 128)
    {
        r.lo = (a.hi >> (s - 64));
        r.hi = 0;
    }
    else
    {
        r.hi = 0;
        r.lo = 0;
    }
    return r;
}
static uint64_t u128_hi(u128 a)
{
    return a.hi;
}
static uint64_t u128_lo(u128 a)
{
    return a.lo;
}
#endif

/* decode text -> bytes */
static bool decode_ulid_text_to_bytes(const char* input, ULID* out)
{
    size_t len;
    int vals[26];
    int i;
#if HAVE_U128
    __uint128_t acc = 0;
#else
    u128 acc = u128_zero();
#endif

    if (!input || !out)
        return false;
    len = strlen(input);
    if (!(len == 25 || len == 26))
        return false;

    for (i = 0; i < (int)len; i++)
    {
        int v = base32_val(input[i]);
        if (v < 0)
            return false;
        vals[i] = v & 0x1F;
    }

#if HAVE_U128
    if (len == 26)
    {
        for (i = 0; i < 26; i++)
            acc = (acc << 5) | (uint64_t)vals[i];
        acc >>= 2;
    }
    else
    {
        for (i = 0; i < 25; i++)
            acc = (acc << 5) | (uint64_t)vals[i];
        acc <<= 3;
    }
    {
        uint64_t high = (uint64_t)(acc >> 64);
        uint64_t low = (uint64_t)(acc & 0xFFFFFFFFFFFFFFFFULL);
        for (i = 0; i < 8; i++)
            out->data[i] = (unsigned char)((high >> (56 - i * 8)) & 0xFF);
        for (i = 0; i < 8; i++)
            out->data[8 + i] = (unsigned char)((low >> (56 - i * 8)) & 0xFF);
    }
#else
    if (len == 26)
    {
        for (i = 0; i < 26; i++)
            acc = u128_lshift_add(acc, (uint64_t)vals[i]);
        acc = u128_rshift(acc, 2);
    }
    else
    {
        for (i = 0; i < 25; i++)
            acc = u128_lshift_add(acc, (uint64_t)vals[i]);
        acc = u128_shl(acc, 3);
    }
    {
        uint64_t high = u128_hi(acc);
        uint64_t low = u128_lo(acc);
        for (i = 0; i < 8; i++)
            out->data[i] = (unsigned char)((high >> (56 - i * 8)) & 0xFF);
        for (i = 0; i < 8; i++)
            out->data[8 + i] = (unsigned char)((low >> (56 - i * 8)) & 0xFF);
    }
#endif

    return true;
}

/* encode bytes -> text (canonical 26 chars) */
static void encode_bytes_to_ulid_text(const ULID* in, char* out_buffer)
{
    int i;
#if HAVE_U128
    __uint128_t acc = 0;
    for (i = 0; i < 16; i++)
        acc = (acc << 8) | (uint64_t)in->data[i];
    acc <<= 2;
    for (i = 25; i >= 0; i--)
    {
        uint8_t v = (uint8_t)(acc & 0x1F);
        out_buffer[i] = base32_alphabet[v];
        acc >>= 5;
    }
#else
    u128 acc = u128_zero();
    for (i = 0; i < 16; i++)
    {
        acc = u128_shl(acc, 8);
        acc.lo |= in->data[i];
    }
    acc = u128_shl(acc, 2);
    for (i = 25; i >= 0; i--)
    {
        uint8_t v = (uint8_t)(acc.lo & 0x1F);
        out_buffer[i] = base32_alphabet[v];
        acc = u128_rshift(acc, 5);
    }
#endif
    out_buffer[26] = '\0';
}

/* portable time in ms */
static int64_t get_time_ms(void)
{
#ifdef _WIN32
    FILETIME ft;
    uint64_t v;
    GetSystemTimeAsFileTime(&ft);
    v = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    /* filetime 100-ns since 1601 -> ms since 1970 */
    return (int64_t)(v / 10000ULL - 11644473600000ULL);
#else
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) == 0)
        return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
    return (int64_t)time(NULL) * 1000;
#endif
}

/* secure random bytes (best-effort) */
static void fill_random_bytes(unsigned char* buf, size_t n)
{
#ifdef _WIN32
    HCRYPTPROV prov;
    if (CryptAcquireContextW(&prov, NULL, NULL, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT | CRYPT_SILENT))
    {
        CryptGenRandom(prov, (DWORD)n, buf);
        CryptReleaseContext(prov, 0);
        return;
    }
#endif
    /* POSIX or fallback: try /dev/urandom */
#ifndef _WIN32
    {
        FILE* f = fopen("/dev/urandom", "rb");
        if (f)
        {
            size_t got = fread(buf, 1, n, f);
            fclose(f);
            if (got == n)
                return;
        }
    }
#endif
    /* fallback pseudo-random */
    srand((unsigned)time(NULL) ^ (unsigned)(get_time_ms() & 0xFFFFFFFF));
    while (n--)
        *buf++ = (unsigned char)(rand() & 0xFF);
}

/* generate bytes */
static void generate_ulid_bytes(ULID* out)
{
    int64_t ts = get_time_ms();
    out->data[0] = (ts >> 40) & 0xFF;
    out->data[1] = (ts >> 32) & 0xFF;
    out->data[2] = (ts >> 24) & 0xFF;
    out->data[3] = (ts >> 16) & 0xFF;
    out->data[4] = (ts >> 8) & 0xFF;
    out->data[5] = ts & 0xFF;
    fill_random_bytes(out->data + 6, 10);
}

/* monotonic generator */
static void generate_ulid_monotonic_bytes(ULID* out)
{
    static int64_t last_time_ms = 0;
    static uint32_t counter = 0;
    int64_t current_time_ms = get_time_ms();

    if (current_time_ms > last_time_ms)
    {
        last_time_ms = current_time_ms;
        counter = 0;
    }
    counter++;

    out->data[0] = (last_time_ms >> 40) & 0xFF;
    out->data[1] = (last_time_ms >> 32) & 0xFF;
    out->data[2] = (last_time_ms >> 24) & 0xFF;
    out->data[3] = (last_time_ms >> 16) & 0xFF;
    out->data[4] = (last_time_ms >> 8) & 0xFF;
    out->data[5] = last_time_ms & 0xFF;

    out->data[6] = (counter >> 24) & 0xFF;
    out->data[7] = (counter >> 16) & 0xFF;
    out->data[8] = (counter >> 8) & 0xFF;
    out->data[9] = (counter)&0xFF;

    fill_random_bytes(out->data + 10, 6);
}

static void generate_ulid_with_ts_bytes(ULID* out, int64_t timestamp_ms)
{
    out->data[0] = (timestamp_ms >> 40) & 0xFF;
    out->data[1] = (timestamp_ms >> 32) & 0xFF;
    out->data[2] = (timestamp_ms >> 24) & 0xFF;
    out->data[3] = (timestamp_ms >> 16) & 0xFF;
    out->data[4] = (timestamp_ms >> 8) & 0xFF;
    out->data[5] = timestamp_ms & 0xFF;
    fill_random_bytes(out->data + 6, 10);
}

static int64_t extract_timestamp_ms_from_ulid_bytes(const ULID* in)
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

/* Postgres functions */

PG_FUNCTION_INFO_V1(ulid_in);
Datum ulid_in(PG_FUNCTION_ARGS)
{
    char* input = PG_GETARG_CSTRING(0);
    ULID* result = (ULID*)palloc(sizeof(ULID));
    if (!decode_ulid_text_to_bytes(input, result))
    {
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                        errmsg("invalid input syntax for type ulid: \"%s\"", input)));
    }
    PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(ulid_out);
Datum ulid_out(PG_FUNCTION_ARGS)
{
    ULID* ulid = (ULID*)PG_GETARG_POINTER(0);
    char* result = (char*)palloc(ULID_TEXT_LEN + 1);
    encode_bytes_to_ulid_text(ulid, result);
    PG_RETURN_CSTRING(result);
}

PG_FUNCTION_INFO_V1(ulid_send);
Datum ulid_send(PG_FUNCTION_ARGS)
{
    ULID* ulid = (ULID*)PG_GETARG_POINTER(0);
    bytea* result = (bytea*)palloc(VARHDRSZ + 16);
    SET_VARSIZE(result, VARHDRSZ + 16);
    memcpy(VARDATA(result), ulid->data, 16);
    PG_RETURN_BYTEA_P(result);
}

PG_FUNCTION_INFO_V1(ulid_recv);
Datum ulid_recv(PG_FUNCTION_ARGS)
{
    StringInfo buf = (StringInfo)PG_GETARG_POINTER(0);
    ULID* result = (ULID*)palloc(sizeof(ULID));
    if (buf->len < 16)
        elog(ERROR, "invalid ULID binary data");
    memcpy(result->data, buf->data, 16);
    PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(ulid_cmp);
Datum ulid_cmp(PG_FUNCTION_ARGS)
{
    ULID* a = (ULID*)PG_GETARG_POINTER(0);
    ULID* b = (ULID*)PG_GETARG_POINTER(1);
    int cmp = memcmp(a->data, b->data, 16);
    if (cmp < 0)
        PG_RETURN_INT32(-1);
    else if (cmp > 0)
        PG_RETURN_INT32(1);
    else
        PG_RETURN_INT32(0);
}

/* boolean ops */
PG_FUNCTION_INFO_V1(ulid_lt);
Datum ulid_lt(PG_FUNCTION_ARGS)
{
    ULID* a = (ULID*)PG_GETARG_POINTER(0);
    ULID* b = (ULID*)PG_GETARG_POINTER(1);
    PG_RETURN_BOOL(memcmp(a->data, b->data, 16) < 0);
}
PG_FUNCTION_INFO_V1(ulid_le);
Datum ulid_le(PG_FUNCTION_ARGS)
{
    ULID* a = (ULID*)PG_GETARG_POINTER(0);
    ULID* b = (ULID*)PG_GETARG_POINTER(1);
    PG_RETURN_BOOL(memcmp(a->data, b->data, 16) <= 0);
}
PG_FUNCTION_INFO_V1(ulid_eq);
Datum ulid_eq(PG_FUNCTION_ARGS)
{
    ULID* a = (ULID*)PG_GETARG_POINTER(0);
    ULID* b = (ULID*)PG_GETARG_POINTER(1);
    PG_RETURN_BOOL(memcmp(a->data, b->data, 16) == 0);
}
PG_FUNCTION_INFO_V1(ulid_ne);
Datum ulid_ne(PG_FUNCTION_ARGS)
{
    ULID* a = (ULID*)PG_GETARG_POINTER(0);
    ULID* b = (ULID*)PG_GETARG_POINTER(1);
    PG_RETURN_BOOL(memcmp(a->data, b->data, 16) != 0);
}
PG_FUNCTION_INFO_V1(ulid_ge);
Datum ulid_ge(PG_FUNCTION_ARGS)
{
    ULID* a = (ULID*)PG_GETARG_POINTER(0);
    ULID* b = (ULID*)PG_GETARG_POINTER(1);
    PG_RETURN_BOOL(memcmp(a->data, b->data, 16) >= 0);
}
PG_FUNCTION_INFO_V1(ulid_gt);
Datum ulid_gt(PG_FUNCTION_ARGS)
{
    ULID* a = (ULID*)PG_GETARG_POINTER(0);
    ULID* b = (ULID*)PG_GETARG_POINTER(1);
    PG_RETURN_BOOL(memcmp(a->data, b->data, 16) > 0);
}

PG_FUNCTION_INFO_V1(ulid_generate);
Datum ulid_generate(PG_FUNCTION_ARGS)
{
    ULID* r = palloc(sizeof(ULID));
    generate_ulid_bytes(r);
    PG_RETURN_POINTER(r);
}

PG_FUNCTION_INFO_V1(ulid_generate_monotonic);
Datum ulid_generate_monotonic(PG_FUNCTION_ARGS)
{
    ULID* r = palloc(sizeof(ULID));
    generate_ulid_monotonic_bytes(r);
    PG_RETURN_POINTER(r);
}

PG_FUNCTION_INFO_V1(ulid_generate_with_timestamp);
Datum ulid_generate_with_timestamp(PG_FUNCTION_ARGS)
{
    int64_t ts = PG_GETARG_INT64(0);
    ULID* r = palloc(sizeof(ULID));
    generate_ulid_with_ts_bytes(r, ts);
    PG_RETURN_POINTER(r);
}

PG_FUNCTION_INFO_V1(ulid_timestamp);
Datum ulid_timestamp(PG_FUNCTION_ARGS)
{
    ULID* u = (ULID*)PG_GETARG_POINTER(0);
    int64_t ts = extract_timestamp_ms_from_ulid_bytes(u);
    PG_RETURN_INT64((int64)ts);
}

PG_FUNCTION_INFO_V1(ulid_to_uuid);
Datum ulid_to_uuid(PG_FUNCTION_ARGS)
{
    ULID* u = (ULID*)PG_GETARG_POINTER(0);
    pg_uuid_t* uuid = (pg_uuid_t*)palloc(UUID_LEN);
    memcpy(uuid->data, u->data, 16);
    PG_RETURN_UUID_P(uuid);
}

PG_FUNCTION_INFO_V1(ulid_from_uuid);
Datum ulid_from_uuid(PG_FUNCTION_ARGS)
{
    pg_uuid_t* uuid = (pg_uuid_t*)PG_GETARG_POINTER(0);
    ULID* r = palloc(sizeof(ULID));
    memcpy(r->data, uuid->data, 16);
    PG_RETURN_POINTER(r);
}

PG_FUNCTION_INFO_V1(ulid_hash);
Datum ulid_hash(PG_FUNCTION_ARGS)
{
    ULID* u = (ULID*)PG_GETARG_POINTER(0);
    uint32_t h = 0;
    int i;
    for (i = 0; i < 16; i++)
        h = h * 31 + u->data[i];
    PG_RETURN_INT32((int32_t)h);
}
