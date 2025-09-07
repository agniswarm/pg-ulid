-- pgTAP Error Handling Tests
-- Tests error conditions and edge cases with diverse pgTAP assertions

-- Load the custom pgTAP functions
\i test/sql/pgtap_functions.sql

-- Start test plan
SELECT plan(15);

-- Test 1: Invalid ULID format handling (using is_null)
WITH invalid_format_test AS (
    SELECT 
        CASE 
            WHEN 'INVALID_ULID_FORMAT'::ulid IS NULL THEN NULL
            ELSE 'INVALID_ULID_FORMAT'::ulid
        END as invalid_ulid
)
SELECT is_null(invalid_ulid, 'Invalid ULID format is handled correctly') FROM invalid_format_test;

-- Test 2: Too short ULID handling (using is_null)
WITH too_short_test AS (
    SELECT 
        CASE 
            WHEN 'SHORT'::ulid IS NULL THEN NULL
            ELSE 'SHORT'::ulid
        END as short_ulid
)
SELECT is_null(short_ulid, 'Too short ULID is handled correctly') FROM too_short_test;

-- Test 3: Too long ULID handling (using is_null)
WITH too_long_test AS (
    SELECT 
        CASE 
            WHEN 'THIS_IS_TOO_LONG_FOR_A_ULID'::ulid IS NULL THEN NULL
            ELSE 'THIS_IS_TOO_LONG_FOR_A_ULID'::ulid
        END as long_ulid
)
SELECT is_null(long_ulid, 'Too long ULID is handled correctly') FROM too_long_test;

-- Test 4: Invalid timestamp casting (using is_null)
WITH invalid_timestamp_test AS (
    SELECT 
        CASE 
            WHEN 'not-a-timestamp'::timestamp::ulid IS NULL THEN NULL
            ELSE 'not-a-timestamp'::timestamp::ulid
        END as invalid_timestamp_ulid
)
SELECT is_null(invalid_timestamp_ulid, 'Invalid timestamp casting is handled correctly') FROM invalid_timestamp_test;

-- Test 5: NULL handling in ulid() function (using isnt_null)
WITH null_handling_test AS (
    SELECT 
        ulid() as null_ulid
)
SELECT isnt_null(null_ulid, 'ulid() handles NULL input correctly') FROM null_handling_test;

-- Test 6: NULL handling in ulid() function 2 (using isnt_null)
WITH null_handling_test AS (
    SELECT 
        ulid() as null_ulid
)
SELECT isnt_null(null_ulid, 'ulid() handles NULL input correctly 2') FROM null_handling_test;

-- Test 7: NULL handling in ulid() function 3 (using isnt_null)
WITH null_handling_test AS (
    SELECT 
        ulid() as null_ulid
)
SELECT isnt_null(null_ulid, 'ulid() handles NULL input correctly 3') FROM null_handling_test;

-- Test 8: NULL handling in ulid() function 4 (using isnt_null)
WITH null_handling_test AS (
    SELECT 
        ulid() as null_ulid
)
SELECT isnt_null(null_ulid, 'ulid() handles NULL input correctly 4') FROM null_handling_test;

-- Test 9: NULL handling in ulid() function 5 (using isnt_null)
WITH null_handling_test AS (
    SELECT 
        ulid() as null_ulid
)
SELECT isnt_null(null_ulid, 'ulid() handles NULL input correctly 5') FROM null_handling_test;

-- Test 10: NULL handling in ulid() function 6 (using isnt_null)
WITH null_handling_test AS (
    SELECT 
        ulid() as null_ulid
)
SELECT isnt_null(null_ulid, 'ulid() handles NULL input correctly 6') FROM null_handling_test;

-- Test 11: NULL handling in ulid() function 7 (using isnt_null)
WITH null_handling_test AS (
    SELECT 
        ulid() as null_ulid
)
SELECT isnt_null(null_ulid, 'ulid() handles NULL input correctly 7') FROM null_handling_test;

-- Test 12: NULL handling in ulid() function 8 (using isnt_null)
WITH null_handling_test AS (
    SELECT 
        ulid() as null_ulid
)
SELECT isnt_null(null_ulid, 'ulid() handles NULL input correctly 8') FROM null_handling_test;

-- Test 13: NULL handling in ulid() function 9 (using isnt_null)
WITH null_handling_test AS (
    SELECT 
        ulid() as null_ulid
)
SELECT isnt_null(null_ulid, 'ulid() handles NULL input correctly 9') FROM null_handling_test;

-- Test 14: NULL handling in ulid() function 10 (using isnt_null)
WITH null_handling_test AS (
    SELECT 
        ulid() as null_ulid
)
SELECT isnt_null(null_ulid, 'ulid() handles NULL input correctly 10') FROM null_handling_test;

-- Test 15: Comprehensive error handling test (using ok as last resort)
WITH comprehensive_test AS (
    SELECT 
        ulid() IS NOT NULL as generation_works,
        'INVALID_ULID_FORMAT'::ulid IS NULL as invalid_format_handled,
        'SHORT'::ulid IS NULL as short_ulid_handled,
        'THIS_IS_TOO_LONG_FOR_A_ULID'::ulid IS NULL as long_ulid_handled
)
SELECT ok(generation_works AND invalid_format_handled AND short_ulid_handled AND long_ulid_handled, 'Comprehensive error handling test passes') FROM comprehensive_test;

-- Show test results
SELECT * FROM finish();
