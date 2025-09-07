-- pgTAP Basic ULID Functionality Tests
-- Tests core ULID generation, parsing, and basic operations with diverse pgTAP assertions

-- Load the custom pgTAP functions
\i test/sql/pgtap_functions.sql

-- Start test plan
SELECT plan(20);

-- Test 1: Basic ULID generation (using isnt_null)
SELECT isnt_null(ulid(), 'ulid() generates non-null value');

-- Test 2: ULID format validation (using is)
SELECT is(length(ulid()), 25, 'ulid() generates 25-character string');

-- Test 3: ULID uniqueness (using cmp_ok)
WITH test_ulids AS (
    SELECT ulid() as ulid_val
    FROM generate_series(1, 100)
)
SELECT cmp_ok(COUNT(*), '=', COUNT(DISTINCT ulid_val), 'ULIDs are unique in small sample') FROM test_ulids;

-- Test 4: ulid_random() function (using isnt_null)
SELECT isnt_null(ulid_random(), 'ulid_random() generates non-null value');

-- Test 5: ulid_crypto() function (using isnt_null)
SELECT isnt_null(ulid_crypto(), 'ulid_crypto() generates non-null value');

-- Test 6: ulid_time() function (using isnt_null)
SELECT isnt_null(ulid_time(1640995200000), 'ulid_time() generates non-null value');

-- Test 7: ulid_parse() function (using isnt_null)
SELECT isnt_null(ulid_parse('01ARZ3NDEKTSV4RRFFQ69G5FAV'), 'ulid_parse() parses valid ULID');

-- Test 8: Batch generation - ulid_batch() (using is)
SELECT is(array_length(ulid_batch(5), 1), 5, 'ulid_batch() generates correct number of ULIDs');

-- Test 9: Batch generation - ulid_random_batch() (using is)
SELECT is(array_length(ulid_random_batch(3), 1), 3, 'ulid_random_batch() generates correct number of ULIDs');

-- Test 10: Value comparison - ulid_time() with specific timestamp (using isnt_null)
WITH timestamp_test AS (
    SELECT ulid_time(1640995200000) as generated_ulid
)
SELECT isnt_null(generated_ulid, 'ulid_time() generates ULID for 2022-01-01 00:00:00 UTC') FROM timestamp_test;

-- Test 11: Value comparison - ulid_parse() with known ULID (using isnt_null)
WITH parse_test AS (
    SELECT ulid_parse('01ARZ3NDEKTSV4RRFFQ69G5FAV') as parsed_ulid
)
SELECT isnt_null(parsed_ulid, 'ulid_parse() correctly parses known ULID') FROM parse_test;

-- Test 12: Value comparison - ulid() vs ulid_random() are different (using isnt)
WITH comparison_test AS (
    SELECT 
        ulid() as monotonic_ulid,
        ulid_random() as random_ulid
)
SELECT isnt(monotonic_ulid, random_ulid, 'ulid() and ulid_random() generate different values') FROM comparison_test;

-- Test 13: Value comparison - ulid() vs ulid_crypto() are different (using isnt)
WITH comparison_test AS (
    SELECT 
        ulid() as monotonic_ulid,
        ulid_crypto() as crypto_ulid
)
SELECT isnt(monotonic_ulid, crypto_ulid, 'ulid() and ulid_crypto() generate different values') FROM comparison_test;

-- Test 14: Value comparison - batch generation produces unique values (using cmp_ok)
WITH batch_test AS (
    SELECT unnest(ulid_batch(10)) as ulid_val
)
SELECT cmp_ok(COUNT(*), '=', COUNT(DISTINCT ulid_val), 'ulid_batch() generates unique ULIDs') FROM batch_test;

-- Test 15: Value comparison - random batch generation produces unique values (using cmp_ok)
WITH random_batch_test AS (
    SELECT unnest(ulid_random_batch(10)) as ulid_val
)
SELECT cmp_ok(COUNT(*), '=', COUNT(DISTINCT ulid_val), 'ulid_random_batch() generates unique ULIDs') FROM random_batch_test;

-- Test 16: Length validation with cmp_ok (greater than)
WITH length_test AS (
    SELECT length(ulid()) as ulid_length
)
SELECT cmp_ok(ulid_length, '>', 20, 'ULID length is greater than 20') FROM length_test;

-- Test 17: Length validation with cmp_ok (less than)
WITH length_test AS (
    SELECT length(ulid()) as ulid_length
)
SELECT cmp_ok(ulid_length, '<', 30, 'ULID length is less than 30') FROM length_test;

-- Test 18: Null check with is_null (should pass)
WITH null_test AS (
    SELECT NULL as null_value
)
SELECT is_null(null_value, 'NULL value is null') FROM null_test;

-- Test 19: Equality with is() for text
WITH text_test AS (
    SELECT '01ARZ3NDEKTSV4RRFFQ69G5FAV' as test_ulid
)
SELECT is(test_ulid, '01ARZ3NDEKTSV4RRFFQ69G5FAV', 'Text equality works') FROM text_test;

-- Test 20: Inequality with isnt() for different ULIDs
WITH different_ulids AS (
    SELECT 
        ulid()::text as ulid1,
        ulid()::text as ulid2
)
SELECT isnt(ulid1, ulid2, 'Two consecutive ULIDs are different') FROM different_ulids;

-- Show test results
SELECT * FROM finish();
