/* src/objectid.c
 *
 * MongoDB ObjectId PostgreSQL extension implementation using libbson.
 * Provides ObjectId type, I/O functions, generation, and utility functions.
 *
 * NOTE: this file assumes libbson >= typical mongo-c-driver API:
 *   bson_oid_init, bson_oid_init_from_string, bson_oid_to_string,
 *   bson_oid_get_time_t, bson_oid_is_valid
 *
 * You must link against libmongoc/libbson when building.
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

/* MongoDB C driver includes */
/* Disable C90 declaration-after-statement warning for BSON headers */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeclaration-after-statement"
#include <bson/bson.h>
#pragma GCC diagnostic pop

#include <mongoc/mongoc.h>

/* PostgreSQL module magic - defined in ulid.c */

/* Internal representation */
typedef struct ObjectId
{
    unsigned char data[12];
} ObjectId;

#define OBJECTID_TEXT_LEN 24
#define OBJECTID_HEX_LEN 24

/* --------------------------------------------------------------------
 * Forward PG function declarations
 * ------------------------------------------------------------------*/
PG_FUNCTION_INFO_V1(objectid_in);
PG_FUNCTION_INFO_V1(objectid_out);
PG_FUNCTION_INFO_V1(objectid_send);
PG_FUNCTION_INFO_V1(objectid_recv);

PG_FUNCTION_INFO_V1(objectid_generate);
PG_FUNCTION_INFO_V1(objectid_generate_random);
PG_FUNCTION_INFO_V1(objectid_generate_with_timestamp);
PG_FUNCTION_INFO_V1(objectid_generate_with_timestamptz);

PG_FUNCTION_INFO_V1(objectid_timestamp);
PG_FUNCTION_INFO_V1(objectid_parse);
PG_FUNCTION_INFO_V1(objectid_time);
PG_FUNCTION_INFO_V1(objectid_to_timestamp);
PG_FUNCTION_INFO_V1(objectid_timestamp_text);

PG_FUNCTION_INFO_V1(objectid_batch);
PG_FUNCTION_INFO_V1(objectid_random_batch);

PG_FUNCTION_INFO_V1(objectid_cmp);
PG_FUNCTION_INFO_V1(objectid_hash);

PG_FUNCTION_INFO_V1(objectid_lt);
PG_FUNCTION_INFO_V1(objectid_le);
PG_FUNCTION_INFO_V1(objectid_eq);
PG_FUNCTION_INFO_V1(objectid_ge);
PG_FUNCTION_INFO_V1(objectid_gt);
PG_FUNCTION_INFO_V1(objectid_ne);

PG_FUNCTION_INFO_V1(objectid_to_bytea_cast);
PG_FUNCTION_INFO_V1(bytea_to_objectid_cast);
PG_FUNCTION_INFO_V1(timestamp_to_objectid_cast);
PG_FUNCTION_INFO_V1(timestamptz_to_objectid_cast);
PG_FUNCTION_INFO_V1(objectid_to_timestamp_cast);
PG_FUNCTION_INFO_V1(objectid_to_timestamptz_cast);
PG_FUNCTION_INFO_V1(text_to_objectid_cast);
PG_FUNCTION_INFO_V1(objectid_to_text_cast);

/* --------------------------------------------------------------------
 * Helper declarations
 * ------------------------------------------------------------------*/
static bool is_valid_hex_string(const char* str, size_t len);

/* convert: copy ObjectId -> bson_oid_t (caller provides output) */
static void objectid_to_bson_oid(const ObjectId* oid, bson_oid_t* out);

/* convert: copy bson_oid_t -> ObjectId */
static void bson_oid_to_objectid(const bson_oid_t* bson_oid, ObjectId* oid);

/* --------------------------------------------------------------------
 * I/O functions
 * ------------------------------------------------------------------*/
Datum objectid_in(PG_FUNCTION_ARGS)
{
    char* input = PG_GETARG_CSTRING(0);
    ObjectId* result;
    bson_oid_t bson_oid;
    size_t len;

    len = strlen(input);

    if (len != OBJECTID_HEX_LEN)
    {
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                        errmsg("invalid ObjectId: expected %d characters, got %zu",
                               OBJECTID_HEX_LEN, len)));
    }

    if (!is_valid_hex_string(input, len))
    {
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                        errmsg("invalid ObjectId: contains non-hexadecimal characters")));
    }

    /* libbson provides a bson_oid_is_valid; it usually takes a const char *.
     * Some versions take length; if your libbson doesn't have this, remove the call.
     */
    if (!bson_oid_is_valid(input, (int)len))
    {
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                        errmsg("invalid ObjectId: malformed hexadecimal string")));
    }

    /* initialize bson_oid from hex string */
    bson_oid_init_from_string(&bson_oid, input);

    result = (ObjectId*)palloc(sizeof(ObjectId));
    bson_oid_to_objectid(&bson_oid, result);

    PG_RETURN_POINTER(result);
}

Datum objectid_out(PG_FUNCTION_ARGS)
{
    ObjectId* oid = (ObjectId*)PG_GETARG_POINTER(0);
    bson_oid_t bson_oid;
    char buf[OBJECTID_TEXT_LEN + 1];

    /* Convert our internal form to a bson_oid_t and then to a hex string */
    objectid_to_bson_oid(oid, &bson_oid);
    /* bson_oid_to_string writes a 24-char hex + '\0' into buf */
    bson_oid_to_string(&bson_oid, buf);

    PG_RETURN_CSTRING(pstrdup(buf));
}

/* binary send/recv */
Datum objectid_send(PG_FUNCTION_ARGS)
{
    ObjectId* oid = (ObjectId*)PG_GETARG_POINTER(0);
    bytea* result;

    result = (bytea*)palloc(VARHDRSZ + sizeof(ObjectId));
    SET_VARSIZE(result, VARHDRSZ + sizeof(ObjectId));
    memcpy(VARDATA(result), oid->data, sizeof(ObjectId));

    PG_RETURN_BYTEA_P(result);
}

Datum objectid_recv(PG_FUNCTION_ARGS)
{
    StringInfo buf = (StringInfo)PG_GETARG_POINTER(0);
    ObjectId* result;

    result = (ObjectId*)palloc(sizeof(ObjectId));
    /* copy raw bytes from message into our struct's data */
    pq_copymsgbytes(buf, (char*)result->data, sizeof(ObjectId));

    PG_RETURN_POINTER(result);
}

/* --------------------------------------------------------------------
 * Generation
 * ------------------------------------------------------------------*/
Datum objectid_generate(PG_FUNCTION_ARGS)
{
    ObjectId* result;
    bson_oid_t bson_oid;

    bson_oid_init(&bson_oid, NULL);

    result = (ObjectId*)palloc(sizeof(ObjectId));
    bson_oid_to_objectid(&bson_oid, result);

    PG_RETURN_POINTER(result);
}

Datum objectid_generate_random(PG_FUNCTION_ARGS)
{
    /* identical to objectid_generate for now */
    return objectid_generate(fcinfo);
}

Datum objectid_generate_with_timestamp(PG_FUNCTION_ARGS)
{
    int64_t ts_seconds = PG_GETARG_INT64(0);
    ObjectId* result;
    bson_oid_t bson_oid;
    uint32_t ts_value;

    bson_oid_init(&bson_oid, NULL);
    ts_value = (uint32_t)ts_seconds;
    memcpy(bson_oid.bytes, &ts_value, 4);

    result = (ObjectId*)palloc(sizeof(ObjectId));
    bson_oid_to_objectid(&bson_oid, result);

    PG_RETURN_POINTER(result);
}

Datum objectid_generate_with_timestamptz(PG_FUNCTION_ARGS)
{
    TimestampTz timestamp = PG_GETARG_TIMESTAMPTZ(0);
    ObjectId* result;
    bson_oid_t bson_oid;
    time_t t;
    uint32_t ts_value;

    /* Convert microseconds to seconds */
    t = (time_t)(timestamp / 1000000LL);

    bson_oid_init(&bson_oid, NULL);
    /* set time-of-oid (manually set timestamp in first 4 bytes) */
    ts_value = (uint32_t)t;
    memcpy(bson_oid.bytes, &ts_value, 4);

    result = (ObjectId*)palloc(sizeof(ObjectId));
    bson_oid_to_objectid(&bson_oid, result);

    PG_RETURN_POINTER(result);
}

/* --------------------------------------------------------------------
 * Utilities: parse / timestamp / conversions
 * ------------------------------------------------------------------*/
Datum objectid_timestamp(PG_FUNCTION_ARGS)
{
    ObjectId* oid = (ObjectId*)PG_GETARG_POINTER(0);
    bson_oid_t bson_oid;
    time_t timestamp;

    objectid_to_bson_oid(oid, &bson_oid);
    timestamp = (time_t)bson_oid_get_time_t(&bson_oid);

    PG_RETURN_INT64((int64)timestamp);
}

Datum objectid_time(PG_FUNCTION_ARGS)
{
    ObjectId* oid = (ObjectId*)PG_GETARG_POINTER(0);
    bson_oid_t bson_oid;
    time_t timestamp;

    objectid_to_bson_oid(oid, &bson_oid);
    timestamp = (time_t)bson_oid_get_time_t(&bson_oid);

    PG_RETURN_INT64((int64)timestamp);
}

Datum objectid_parse(PG_FUNCTION_ARGS)
{
    text* input = PG_GETARG_TEXT_PP(0);
    ObjectId* result;
    bson_oid_t bson_oid;
    char* input_str;
    size_t len;

    input_str = text_to_cstring(input);
    len = strlen(input_str);

    if (len != OBJECTID_HEX_LEN)
    {
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                        errmsg("invalid ObjectId: expected %d characters, got %zu",
                               OBJECTID_HEX_LEN, len)));
    }

    if (!is_valid_hex_string(input_str, len))
    {
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                        errmsg("invalid ObjectId: contains non-hexadecimal characters")));
    }

    if (!bson_oid_is_valid(input_str, (int)len))
    {
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                        errmsg("invalid ObjectId: malformed hexadecimal string")));
    }

    bson_oid_init_from_string(&bson_oid, input_str);

    result = (ObjectId*)palloc(sizeof(ObjectId));
    bson_oid_to_objectid(&bson_oid, result);

    PG_RETURN_POINTER(result);
}

Datum objectid_to_timestamp(PG_FUNCTION_ARGS)
{
    ObjectId* oid = (ObjectId*)PG_GETARG_POINTER(0);
    bson_oid_t bson_oid;
    time_t timestamp;
    TimestampTz result_ts;

    objectid_to_bson_oid(oid, &bson_oid);
    timestamp = (time_t)bson_oid_get_time_t(&bson_oid);

    result_ts = (TimestampTz)timestamp * 1000000LL; // Convert seconds to microseconds
    PG_RETURN_TIMESTAMPTZ(result_ts);
}

Datum objectid_timestamp_text(PG_FUNCTION_ARGS)
{
    ObjectId* oid = (ObjectId*)PG_GETARG_POINTER(0);
    bson_oid_t bson_oid;
    time_t timestamp;
    char* ts_str;
    text* result;

    objectid_to_bson_oid(oid, &bson_oid);
    timestamp = (time_t)bson_oid_get_time_t(&bson_oid);

    ts_str = psprintf("%lld", (long long)timestamp);
    result = cstring_to_text(ts_str);
    pfree(ts_str);

    PG_RETURN_TEXT_P(result);
}

/* --------------------------------------------------------------------
 * Batch creation (returns array of ObjectId pointers)
 * NOTE: you must provide OBJECTIDOID Oid in your extension, or replace
 *       construct_array's first argument with the correct Oid for your
 *       custom type. I left a TODO where that is required.
 * ------------------------------------------------------------------*/
Datum objectid_batch(PG_FUNCTION_ARGS)
{
    int32 count = PG_GETARG_INT32(0);
    ObjectId** oids;
    Datum* elements;
    ArrayType* result;
    int i;

    if (count <= 0 || count > 10000)
    {
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("batch count must be between 1 and 10000")));
    }

    oids = (ObjectId**)palloc(count * sizeof(ObjectId*));
    elements = (Datum*)palloc(count * sizeof(Datum));

    for (i = 0; i < count; i++)
    {
        bson_oid_t bson_oid;
        bson_oid_init(&bson_oid, NULL);

        oids[i] = (ObjectId*)palloc(sizeof(ObjectId));
        bson_oid_to_objectid(&bson_oid, oids[i]);
        elements[i] = PointerGetDatum(oids[i]);
    }

    /*
     * TODO: Replace OBJECTIDOID below with the Oid of your ObjectId base type.
     * For example, if you created the type and saved its Oid in a constant,
     * use that constant instead of OBJECTIDOID. If you prefer returning
     * bytea[], change the element type and construct accordingly.
     */
#ifdef OBJECTIDOID
    result = construct_array(elements, count, OBJECTIDOID, sizeof(ObjectId), true, 'i');
#else
    ereport(
        ERROR,
        (errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
         errmsg(
             "OBJECTIDOID is not defined; please set the element type Oid for construct_array")));
#endif

    PG_RETURN_ARRAYTYPE_P(result);
}

Datum objectid_random_batch(PG_FUNCTION_ARGS)
{
    /* same as objectid_batch for now */
    return objectid_batch(fcinfo);
}

/* --------------------------------------------------------------------
 * Comparison/hash/operators
 * ------------------------------------------------------------------*/
Datum objectid_cmp(PG_FUNCTION_ARGS)
{
    ObjectId* a = (ObjectId*)PG_GETARG_POINTER(0);
    ObjectId* b = (ObjectId*)PG_GETARG_POINTER(1);
    int cmp = memcmp(a->data, b->data, sizeof(a->data));

    if (cmp < 0)
        PG_RETURN_INT32(-1);
    else if (cmp > 0)
        PG_RETURN_INT32(1);
    else
        PG_RETURN_INT32(0);
}

Datum objectid_hash(PG_FUNCTION_ARGS)
{
    ObjectId* oid = (ObjectId*)PG_GETARG_POINTER(0);
    uint32 hash = 0;
    int i;

    for (i = 0; i < (int)sizeof(oid->data); i++)
    {
        hash = hash * 31 + oid->data[i];
    }

    PG_RETURN_UINT32(hash);
}

Datum objectid_lt(PG_FUNCTION_ARGS)
{
    ObjectId* a = (ObjectId*)PG_GETARG_POINTER(0);
    ObjectId* b = (ObjectId*)PG_GETARG_POINTER(1);
    PG_RETURN_BOOL(memcmp(a->data, b->data, sizeof(a->data)) < 0);
}
Datum objectid_le(PG_FUNCTION_ARGS)
{
    ObjectId* a = (ObjectId*)PG_GETARG_POINTER(0);
    ObjectId* b = (ObjectId*)PG_GETARG_POINTER(1);
    PG_RETURN_BOOL(memcmp(a->data, b->data, sizeof(a->data)) <= 0);
}
Datum objectid_eq(PG_FUNCTION_ARGS)
{
    ObjectId* a = (ObjectId*)PG_GETARG_POINTER(0);
    ObjectId* b = (ObjectId*)PG_GETARG_POINTER(1);
    PG_RETURN_BOOL(memcmp(a->data, b->data, sizeof(a->data)) == 0);
}
Datum objectid_ge(PG_FUNCTION_ARGS)
{
    ObjectId* a = (ObjectId*)PG_GETARG_POINTER(0);
    ObjectId* b = (ObjectId*)PG_GETARG_POINTER(1);
    PG_RETURN_BOOL(memcmp(a->data, b->data, sizeof(a->data)) >= 0);
}
Datum objectid_gt(PG_FUNCTION_ARGS)
{
    ObjectId* a = (ObjectId*)PG_GETARG_POINTER(0);
    ObjectId* b = (ObjectId*)PG_GETARG_POINTER(1);
    PG_RETURN_BOOL(memcmp(a->data, b->data, sizeof(a->data)) > 0);
}
Datum objectid_ne(PG_FUNCTION_ARGS)
{
    ObjectId* a = (ObjectId*)PG_GETARG_POINTER(0);
    ObjectId* b = (ObjectId*)PG_GETARG_POINTER(1);
    PG_RETURN_BOOL(memcmp(a->data, b->data, sizeof(a->data)) != 0);
}

/* --------------------------------------------------------------------
 * Casts to/from bytea / timestamps / text
 * ------------------------------------------------------------------*/
Datum objectid_to_bytea_cast(PG_FUNCTION_ARGS)
{
    ObjectId* oid = (ObjectId*)PG_GETARG_POINTER(0);
    bytea* result;

    result = (bytea*)palloc(VARHDRSZ + sizeof(ObjectId));
    SET_VARSIZE(result, VARHDRSZ + sizeof(ObjectId));
    memcpy(VARDATA(result), oid->data, sizeof(ObjectId));

    PG_RETURN_BYTEA_P(result);
}

Datum bytea_to_objectid_cast(PG_FUNCTION_ARGS)
{
    bytea* input = PG_GETARG_BYTEA_PP(0);
    ObjectId* result;
    int dlen = VARSIZE_ANY_EXHDR(input);

    if (dlen != (int)sizeof(ObjectId))
    {
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_BINARY_REPRESENTATION),
                 errmsg("invalid ObjectId: expected %zu bytes, got %d", sizeof(ObjectId), dlen)));
    }

    result = (ObjectId*)palloc(sizeof(ObjectId));
    memcpy(result->data, VARDATA_ANY(input), sizeof(ObjectId));

    PG_RETURN_POINTER(result);
}

Datum timestamp_to_objectid_cast(PG_FUNCTION_ARGS)
{
    Timestamp timestamp = PG_GETARG_TIMESTAMP(0);
    ObjectId* result;
    bson_oid_t bson_oid;
    time_t time_val;
    uint32_t ts_val;

    /* Timestamp is microseconds since epoch */
    time_val = (time_t)(timestamp / 1000000LL);

    bson_oid_init(&bson_oid, NULL);
    // Manually set the timestamp in the ObjectId (first 4 bytes)
    ts_val = (uint32_t)time_val;
    memcpy(bson_oid.bytes, &ts_val, 4);

    result = (ObjectId*)palloc(sizeof(ObjectId));
    bson_oid_to_objectid(&bson_oid, result);

    PG_RETURN_POINTER(result);
}

Datum timestamptz_to_objectid_cast(PG_FUNCTION_ARGS)
{
    TimestampTz timestamp = PG_GETARG_TIMESTAMPTZ(0);
    ObjectId* result;
    bson_oid_t bson_oid;
    time_t time_val;
    uint32_t ts_val;

    time_val = (time_t)(timestamp / 1000000LL);

    bson_oid_init(&bson_oid, NULL);
    // Manually set the timestamp in the ObjectId (first 4 bytes)
    ts_val = (uint32_t)time_val;
    memcpy(bson_oid.bytes, &ts_val, 4);

    result = (ObjectId*)palloc(sizeof(ObjectId));
    bson_oid_to_objectid(&bson_oid, result);

    PG_RETURN_POINTER(result);
}

Datum objectid_to_timestamp_cast(PG_FUNCTION_ARGS)
{
    ObjectId* oid = (ObjectId*)PG_GETARG_POINTER(0);
    bson_oid_t bson_oid;
    time_t timestamp;
    Timestamp result_ts;

    objectid_to_bson_oid(oid, &bson_oid);
    timestamp = (time_t)bson_oid_get_time_t(&bson_oid);

    result_ts = (Timestamp)timestamp * 1000000LL;

    PG_RETURN_TIMESTAMP(result_ts);
}

Datum objectid_to_timestamptz_cast(PG_FUNCTION_ARGS)
{
    ObjectId* oid = (ObjectId*)PG_GETARG_POINTER(0);
    bson_oid_t bson_oid;
    time_t timestamp;
    TimestampTz result_ts;

    objectid_to_bson_oid(oid, &bson_oid);
    timestamp = (time_t)bson_oid_get_time_t(&bson_oid);

    result_ts = (TimestampTz)timestamp * 1000000LL;

    PG_RETURN_TIMESTAMPTZ(result_ts);
}

Datum text_to_objectid_cast(PG_FUNCTION_ARGS)
{
    text* input = PG_GETARG_TEXT_PP(0);
    ObjectId* result;
    bson_oid_t bson_oid;
    char* input_str;

    input_str = text_to_cstring(input);

    if (!bson_oid_is_valid(input_str, (int)strlen(input_str)))
    {
        ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                        errmsg("invalid ObjectId: malformed hexadecimal string")));
    }

    bson_oid_init_from_string(&bson_oid, input_str);

    result = (ObjectId*)palloc(sizeof(ObjectId));
    bson_oid_to_objectid(&bson_oid, result);

    PG_RETURN_POINTER(result);
}

Datum objectid_to_text_cast(PG_FUNCTION_ARGS)
{
    ObjectId* oid = (ObjectId*)PG_GETARG_POINTER(0);
    bson_oid_t bson_oid;
    char buf[OBJECTID_TEXT_LEN + 1];

    objectid_to_bson_oid(oid, &bson_oid);
    bson_oid_to_string(&bson_oid, buf);

    PG_RETURN_CSTRING(pstrdup(buf));
}

/* --------------------------------------------------------------------
 * Helper implementations
 * ------------------------------------------------------------------*/
static bool is_valid_hex_string(const char* str, size_t len)
{
    size_t i;

    for (i = 0; i < len; i++)
    {
        char c = str[i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
        {
            return false;
        }
    }

    return true;
}


/* copy ObjectId bytes into a bson_oid_t */
static void objectid_to_bson_oid(const ObjectId* oid, bson_oid_t* out)
{
    /* libbson's bson_oid_t typically holds a 12-byte array called bytes */
    memcpy(out->bytes, oid->data, sizeof(oid->data));
}

/* copy bson_oid_t bytes into our internal representation */
static void bson_oid_to_objectid(const bson_oid_t* bson_oid, ObjectId* oid)
{
    memcpy(oid->data, bson_oid->bytes, sizeof(oid->data));
}
