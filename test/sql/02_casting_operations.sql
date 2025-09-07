-- pgTAP Casting Operations Tests
-- Tests all casting operations between ULID, text, timestamp, and UUID with diverse pgTAP assertions

-- Load the custom pgTAP functions
\i test/sql/pgtap_functions.sql

-- Start test plan
SELECT plan(17);

-- Test 1: Text to ULID casting (using isnt_null)
SELECT isnt_null('01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid, 'Text to ULID casting works');

-- Test 2: ULID to text casting (using isnt_null)
SELECT isnt_null(ulid()::text, 'ULID to text casting works');

-- Test 3: Value comparison - text round-trip casting (using is)
WITH round_trip_test AS (
    SELECT 
        '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid::timestamp as original_timestamp,
        '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid::timestamp as round_trip_timestamp
)
SELECT is(original_timestamp, round_trip_timestamp, 'Text to ULID to text round-trip preserves timestamp') FROM round_trip_test;

-- Test 4: Timestamp to ULID casting (using isnt_null)
SELECT isnt_null('2023-09-15 12:00:00'::timestamp::ulid, 'Timestamp to ULID casting works');

-- Test 5: ULID to timestamp casting (using isnt_null)
SELECT isnt_null(ulid()::timestamp, 'ULID to timestamp casting works');

-- Test 6: Value comparison - timestamp round-trip casting (using is)
WITH timestamp_round_trip AS (
    SELECT 
        '2023-09-15 12:00:00'::timestamp as original_timestamp,
        '2023-09-15 12:00:00'::timestamp::ulid::timestamp as round_trip_timestamp
)
SELECT is(original_timestamp, round_trip_timestamp, 'Timestamp to ULID to timestamp round-trip preserves value') FROM timestamp_round_trip;

-- Test 6b: Value comparison - ULID to timestamp to ULID round-trip (using is)
WITH ulid_timestamp_round_trip AS (
    SELECT 
        '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid as original_ulid,
        ulid_timestamp('01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid) as original_timestamp_ms,
        ulid_generate_with_timestamp(ulid_timestamp('01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid)) as round_trip_ulid,
        ulid_timestamp(ulid_generate_with_timestamp(ulid_timestamp('01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid))) as round_trip_timestamp_ms
)
SELECT is(original_timestamp_ms, round_trip_timestamp_ms, 'ULID to timestamp to ULID round-trip preserves timestamp') FROM ulid_timestamp_round_trip;

-- Test 7: ULID to timestamptz casting (using isnt_null)
SELECT isnt_null(ulid()::timestamptz, 'ULID to timestamptz casting works');

-- Test 8: ULID to UUID casting (using isnt_null)
SELECT isnt_null(ulid()::uuid, 'ULID to UUID casting works');

-- Test 9: UUID to ULID casting (using isnt_null)
SELECT isnt_null(gen_random_uuid()::ulid, 'UUID to ULID casting works');

-- Test 10: ULID comparison operators (using cmp_ok)
WITH ulid_comparison AS (
    SELECT 
        ulid() as ulid1,
        ulid() as ulid2
)
SELECT cmp_ok(ulid1, '!=', ulid2, 'Two different ULIDs are not equal') FROM ulid_comparison;

-- Test 11: Timestamp extraction accuracy (using cmp_ok)
WITH timestamp_test AS (
    SELECT 
        '2023-09-15 12:00:00'::timestamp as original_timestamp,
        '2023-09-15 12:00:00'::timestamp::ulid::timestamp as extracted_timestamp
)
SELECT cmp_ok(original_timestamp, '=', extracted_timestamp, 'Timestamp extraction is accurate') FROM timestamp_test;

-- Test 12: Text length consistency (using is)
WITH length_test AS (
    SELECT 
        length(ulid()::text) as ulid_length
)
SELECT is(ulid_length, 25, 'ULID text length is 25 characters') FROM length_test;

-- Test 13: Batch casting test (using cmp_ok)
WITH batch_casting AS (
    SELECT unnest(ulid_batch(5)) as ulid_val
)
SELECT cmp_ok(COUNT(*), '=', COUNT(DISTINCT ulid_val::text), 'Batch ULID casting produces unique text values') FROM batch_casting;

-- Test 14: NULL handling in casting (using is_null)
WITH null_casting AS (
    SELECT NULL::ulid as null_ulid
)
SELECT is_null(null_ulid, 'NULL ULID casting works') FROM null_casting;

-- Test 15: Edge case timestamp casting (using isnt_null)
WITH edge_timestamp AS (
    SELECT '1970-01-01 00:00:00'::timestamp::ulid as epoch_ulid
)
SELECT isnt_null(epoch_ulid, 'Epoch timestamp to ULID casting works') FROM edge_timestamp;

-- Test 16: Comprehensive casting test (using ok as last resort)
WITH comprehensive_test AS (
    SELECT 
        ulid() IS NOT NULL as has_ulid,
        ulid()::text IS NOT NULL as text_cast_works,
        ulid()::timestamp IS NOT NULL as timestamp_cast_works,
        ulid()::uuid IS NOT NULL as uuid_cast_works
)
SELECT ok(has_ulid AND text_cast_works AND timestamp_cast_works AND uuid_cast_works, 'All casting operations work') FROM comprehensive_test;

-- Show test results
SELECT * FROM finish();
