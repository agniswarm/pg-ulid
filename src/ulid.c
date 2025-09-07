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

PG_MODULE_MAGIC;

// Forward declarations
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

// ULID type definition - 16 bytes binary
typedef struct ULID
{
    unsigned char data[16];
} ULID;

// Crockford's Base32 alphabet
static const char base32_alphabet[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

// Static variables for monotonic ULID generation (moved to function scope)

// Base32 decoding table
static const int base32_decode[256] = {
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
     0,  1,  2,  3,  4,  5,  6,  7,  8,  9, -1, -1, -1, -1, -1, -1,
    -1, 10, 11, 12, 13, 14, 15, 16, 17,  1, 18, 19,  1, 20, 21, 22,
    23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, -1, -1, -1, -1, -1,
    -1, 10, 11, 12, 13, 14, 15, 16, 17,  1, 18, 19,  1, 20, 21, 22,
    23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
};

// Helper function to decode Base32
static bool decode_base32(const char *input, ULID *ulid)
{
    int bit_count = 0;
    int byte_count = 0;
    unsigned long long buffer = 0;
    int i;
    char c;
    int val;
    
    if (strlen(input) != 26)
        return false;
    
    // Decode 26 Base32 characters to 16 bytes
    for (i = 0; i < 26; i++) {
        c = toupper(input[i]);
        val = base32_decode[(unsigned char)c];
        
        if (val == -1)
            return false;
        
        buffer = (buffer << 5) | val;
        bit_count += 5;
        
        if (bit_count >= 8) {
            ulid->data[byte_count] = (buffer >> (bit_count - 8)) & 0xFF;
            bit_count -= 8;
            byte_count++;
        }
    }
    
    return byte_count == 16;
}

// Helper function to encode to Base32
static void encode_base32(const ULID *ulid, char *output)
{
    int bit_count = 0;
    int char_count = 0;
    unsigned long long buffer = 0;
    int i;
    
    // Encode 16 bytes to 26 Base32 characters
    for (i = 0; i < 16; i++) {
        buffer = (buffer << 8) | ulid->data[i];
        bit_count += 8;
        
        while (bit_count >= 5) {
            output[char_count] = base32_alphabet[(buffer >> (bit_count - 5)) & 0x1F];
            bit_count -= 5;
            char_count++;
        }
    }
    
    output[26] = '\0';
}

// Generate random ULID
static void generate_ulid(ULID *ulid)
{
    struct timespec ts;
    uint64_t timestamp;
    int i;
    
    // Get current timestamp in milliseconds
    clock_gettime(CLOCK_REALTIME, &ts);
    timestamp = (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
    
    // Store timestamp in first 6 bytes (48 bits)
    ulid->data[0] = (timestamp >> 40) & 0xFF;
    ulid->data[1] = (timestamp >> 32) & 0xFF;
    ulid->data[2] = (timestamp >> 24) & 0xFF;
    ulid->data[3] = (timestamp >> 16) & 0xFF;
    ulid->data[4] = (timestamp >> 8) & 0xFF;
    ulid->data[5] = timestamp & 0xFF;
    
    // Generate 10 bytes of random data
    for (i = 6; i < 16; i++) {
        ulid->data[i] = (unsigned char)(random() & 0xFF);
    }
}

// Input function for ULID type
PG_FUNCTION_INFO_V1(ulid_in);
Datum
ulid_in(PG_FUNCTION_ARGS)
{
    char *input = PG_GETARG_CSTRING(0);
    ULID *result = (ULID *) palloc(sizeof(ULID));
    
    if (!decode_base32(input, result)) {
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                 errmsg("invalid input syntax for type ulid: \"%s\"", input)));
    }
    
    PG_RETURN_POINTER(result);
}

// Output function for ULID type
PG_FUNCTION_INFO_V1(ulid_out);
Datum
ulid_out(PG_FUNCTION_ARGS)
{
    ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
    char *result = (char *) palloc(27); // ULID string length + null terminator
    
    encode_base32(ulid, result);
    
    PG_RETURN_CSTRING(result);
}

// Binary send function for ULID type
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

// Binary receive function for ULID type
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

// Comparison function for ULID type
PG_FUNCTION_INFO_V1(ulid_cmp);
Datum
ulid_cmp(PG_FUNCTION_ARGS)
{
    ULID *a = (ULID *) PG_GETARG_POINTER(0);
    ULID *b = (ULID *) PG_GETARG_POINTER(1);
    
    int result = memcmp(a->data, b->data, 16);
    
    if (result < 0)
        PG_RETURN_INT32(-1);
    else if (result > 0)
        PG_RETURN_INT32(1);
    else
        PG_RETURN_INT32(0);
}

// Boolean comparison functions for operators
PG_FUNCTION_INFO_V1(ulid_lt);
Datum
ulid_lt(PG_FUNCTION_ARGS)
{
    ULID *a = (ULID *) PG_GETARG_POINTER(0);
    ULID *b = (ULID *) PG_GETARG_POINTER(1);
    
    int result = memcmp(a->data, b->data, 16);
    PG_RETURN_BOOL(result < 0);
}

PG_FUNCTION_INFO_V1(ulid_le);
Datum
ulid_le(PG_FUNCTION_ARGS)
{
    ULID *a = (ULID *) PG_GETARG_POINTER(0);
    ULID *b = (ULID *) PG_GETARG_POINTER(1);
    
    int result = memcmp(a->data, b->data, 16);
    PG_RETURN_BOOL(result <= 0);
}

PG_FUNCTION_INFO_V1(ulid_eq);
Datum
ulid_eq(PG_FUNCTION_ARGS)
{
    ULID *a = (ULID *) PG_GETARG_POINTER(0);
    ULID *b = (ULID *) PG_GETARG_POINTER(1);
    
    int result = memcmp(a->data, b->data, 16);
    PG_RETURN_BOOL(result == 0);
}

PG_FUNCTION_INFO_V1(ulid_ge);
Datum
ulid_ge(PG_FUNCTION_ARGS)
{
    ULID *a = (ULID *) PG_GETARG_POINTER(0);
    ULID *b = (ULID *) PG_GETARG_POINTER(1);
    
    int result = memcmp(a->data, b->data, 16);
    PG_RETURN_BOOL(result >= 0);
}

PG_FUNCTION_INFO_V1(ulid_gt);
Datum
ulid_gt(PG_FUNCTION_ARGS)
{
    ULID *a = (ULID *) PG_GETARG_POINTER(0);
    ULID *b = (ULID *) PG_GETARG_POINTER(1);
    
    int result = memcmp(a->data, b->data, 16);
    PG_RETURN_BOOL(result > 0);
}

PG_FUNCTION_INFO_V1(ulid_ne);
Datum
ulid_ne(PG_FUNCTION_ARGS)
{
    ULID *a = (ULID *) PG_GETARG_POINTER(0);
    ULID *b = (ULID *) PG_GETARG_POINTER(1);
    
    int result = memcmp(a->data, b->data, 16);
    PG_RETURN_BOOL(result != 0);
}

// Generate ULID function
PG_FUNCTION_INFO_V1(ulid_generate);
Datum
ulid_generate(PG_FUNCTION_ARGS)
{
    ULID *result = (ULID *) palloc(sizeof(ULID));
    generate_ulid(result);
    PG_RETURN_POINTER(result);
}

// Generate monotonic ULID function
PG_FUNCTION_INFO_V1(ulid_generate_monotonic);
Datum
ulid_generate_monotonic(PG_FUNCTION_ARGS)
{
    ULID *result = (ULID *) palloc(sizeof(ULID));
    int64_t current_time_ms;
    int i;
    static int64_t last_time_ms = 0;
    static uint64_t monotonic_counter = 0;
    static bool initialized = false;
    
    // Get current timestamp in milliseconds
    current_time_ms = (int64_t)(GetCurrentTimestamp() / 1000);
    
    if (!initialized) {
        // First call - initialize with current timestamp
        last_time_ms = current_time_ms;
        monotonic_counter = 0;
        initialized = true;
    }
    
    // Always use the last timestamp for consistency within the same session
    // Store timestamp in first 6 bytes (48 bits)
    result->data[0] = (last_time_ms >> 40) & 0xFF;
    result->data[1] = (last_time_ms >> 32) & 0xFF;
    result->data[2] = (last_time_ms >> 24) & 0xFF;
    result->data[3] = (last_time_ms >> 16) & 0xFF;
    result->data[4] = (last_time_ms >> 8) & 0xFF;
    result->data[5] = last_time_ms & 0xFF;
    
    // Always increment counter for true monotonicity
    monotonic_counter++;
    
    // Store counter in bytes 6-9 (32 bits)
    result->data[6] = (monotonic_counter >> 24) & 0xFF;
    result->data[7] = (monotonic_counter >> 16) & 0xFF;
    result->data[8] = (monotonic_counter >> 8) & 0xFF;
    result->data[9] = monotonic_counter & 0xFF;
    
    // Generate random data for remaining bytes
    for (i = 10; i < 16; i++) {
        result->data[i] = (unsigned char)(random() & 0xFF);
    }
    
    // Update timestamp only if we've moved to a new millisecond
    if (current_time_ms > last_time_ms) {
        last_time_ms = current_time_ms;
    }
    
    PG_RETURN_POINTER(result);
}

// Extract timestamp from ULID
PG_FUNCTION_INFO_V1(ulid_timestamp);
Datum
ulid_timestamp(PG_FUNCTION_ARGS)
{
    ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
    
    // Extract timestamp from first 6 bytes (48 bits)
    uint64_t timestamp = 0;
    timestamp |= (uint64_t)ulid->data[0] << 40;
    timestamp |= (uint64_t)ulid->data[1] << 32;
    timestamp |= (uint64_t)ulid->data[2] << 24;
    timestamp |= (uint64_t)ulid->data[3] << 16;
    timestamp |= (uint64_t)ulid->data[4] << 8;
    timestamp |= (uint64_t)ulid->data[5];
    
    PG_RETURN_INT64(timestamp);
}

// Convert ULID to UUID
PG_FUNCTION_INFO_V1(ulid_to_uuid);
Datum
ulid_to_uuid(PG_FUNCTION_ARGS)
{
    ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
    pg_uuid_t *uuid = (pg_uuid_t *) palloc(UUID_LEN);
    
    // Convert ULID bytes to UUID format
    // ULID: 48-bit timestamp + 80-bit random
    // UUID: 32-bit time_low + 16-bit time_mid + 16-bit time_hi + 16-bit clock_seq + 48-bit node
    
    // Use the random part of ULID for UUID generation
    // Map ULID bytes 6-15 (80 bits of randomness) to UUID format
    uuid->data[0] = ulid->data[6];
    uuid->data[1] = ulid->data[7];
    uuid->data[2] = ulid->data[8];
    uuid->data[3] = ulid->data[9];
    uuid->data[4] = ulid->data[10];
    uuid->data[5] = ulid->data[11];
    uuid->data[6] = ulid->data[12];
    uuid->data[7] = ulid->data[13];
    uuid->data[8] = ulid->data[14];
    uuid->data[9] = ulid->data[15];
    
    // Set version 4 (random) and variant bits
    uuid->data[6] = (uuid->data[6] & 0x0F) | 0x40; // Version 4
    uuid->data[8] = (uuid->data[8] & 0x3F) | 0x80; // Variant bits
    
    PG_RETURN_UUID_P(uuid);
}

// Convert UUID to ULID
PG_FUNCTION_INFO_V1(ulid_from_uuid);
Datum
ulid_from_uuid(PG_FUNCTION_ARGS)
{
    pg_uuid_t *uuid = (pg_uuid_t *) PG_GETARG_POINTER(0);
    ULID *result = (ULID *) palloc(sizeof(ULID));
    
    // Get current timestamp in milliseconds
    int64_t timestamp_ms = (int64_t)(GetCurrentTimestamp() / 1000);
    
    // Store timestamp in first 6 bytes (48 bits)
    result->data[0] = (timestamp_ms >> 40) & 0xFF;
    result->data[1] = (timestamp_ms >> 32) & 0xFF;
    result->data[2] = (timestamp_ms >> 24) & 0xFF;
    result->data[3] = (timestamp_ms >> 16) & 0xFF;
    result->data[4] = (timestamp_ms >> 8) & 0xFF;
    result->data[5] = timestamp_ms & 0xFF;
    
    // Use UUID bytes for the random part of ULID
    // Map UUID bytes to ULID bytes 6-15 (80 bits of randomness)
    result->data[6] = uuid->data[0];
    result->data[7] = uuid->data[1];
    result->data[8] = uuid->data[2];
    result->data[9] = uuid->data[3];
    result->data[10] = uuid->data[4];
    result->data[11] = uuid->data[5];
    result->data[12] = uuid->data[6];
    result->data[13] = uuid->data[7];
    result->data[14] = uuid->data[8];
    result->data[15] = uuid->data[9];
    
    PG_RETURN_POINTER(result);
}

// Hash function for ULID type
PG_FUNCTION_INFO_V1(ulid_hash);
Datum
ulid_hash(PG_FUNCTION_ARGS)
{
    ULID *ulid = (ULID *) PG_GETARG_POINTER(0);
    
    // Simple hash function - sum of bytes
    uint32_t hash = 0;
    for (int i = 0; i < 16; i++) {
        hash = hash * 31 + ulid->data[i];
    }
    
    PG_RETURN_INT32((int32_t)hash);
}

// Generate ULID with specific timestamp
PG_FUNCTION_INFO_V1(ulid_generate_with_timestamp);
Datum
ulid_generate_with_timestamp(PG_FUNCTION_ARGS)
{
    int64_t timestamp_ms = PG_GETARG_INT64(0);
    ULID *result = (ULID *) palloc(sizeof(ULID));
    int i;
    
    // Store timestamp in first 6 bytes (48 bits)
    result->data[0] = (timestamp_ms >> 40) & 0xFF;
    result->data[1] = (timestamp_ms >> 32) & 0xFF;
    result->data[2] = (timestamp_ms >> 24) & 0xFF;
    result->data[3] = (timestamp_ms >> 16) & 0xFF;
    result->data[4] = (timestamp_ms >> 8) & 0xFF;
    result->data[5] = timestamp_ms & 0xFF;
    
    // Generate 10 bytes of random data
    for (i = 6; i < 16; i++) {
        result->data[i] = (unsigned char)(random() & 0xFF);
    }
    
    PG_RETURN_POINTER(result);
}
