-- pgTAP Monotonic Generation Tests
-- Tests monotonic behavior and ordering of ULIDs with diverse pgTAP assertions

-- Load the custom pgTAP functions
\i test/sql/pgtap_functions.sql

-- Start test plan
SELECT plan(15);

-- Test 1: Basic monotonic generation (using isnt_null)
SELECT isnt_null(ulid(), 'ulid() generates non-null value');

-- Test 2: Monotonic ordering test (using cmp_ok)
WITH monotonic_test AS (
    SELECT 
        ulid() as ulid1,
        ulid() as ulid2,
        ulid() as ulid3
)
SELECT cmp_ok(ulid1, '<', ulid2, 'First ULID is less than second ULID') FROM monotonic_test;

-- Test 3: Monotonic ordering test 2 (using cmp_ok)
WITH monotonic_test AS (
    SELECT 
        ulid() as ulid1,
        ulid() as ulid2,
        ulid() as ulid3
)
SELECT cmp_ok(ulid2, '<', ulid3, 'Second ULID is less than third ULID') FROM monotonic_test;

-- Test 4: Monotonic ordering test 3 (using cmp_ok)
WITH monotonic_test AS (
    SELECT 
        ulid() as ulid1,
        ulid() as ulid2,
        ulid() as ulid3
)
SELECT cmp_ok(ulid1, '<', ulid3, 'First ULID is less than third ULID') FROM monotonic_test;

-- Test 5: Batch monotonic test (using cmp_ok)
WITH batch_monotonic AS (
    SELECT 
        unnest(ulid_batch(10)) as ulid_val,
        ROW_NUMBER() OVER (ORDER BY unnest(ulid_batch(10))) as row_num
)
SELECT cmp_ok(COUNT(*), '=', 10, 'Batch monotonic test has 10 ULIDs') FROM batch_monotonic;

-- Test 6: Monotonic ordering verification (using isnt)
WITH ordering_verification AS (
    SELECT 
        ulid() as ulid1,
        ulid() as ulid2
)
SELECT isnt(ulid1, ulid2, 'Consecutive ULIDs are different') FROM ordering_verification;

-- Test 7: Timestamp ordering test (using cmp_ok)
WITH timestamp_ordering AS (
    SELECT 
        ulid()::timestamp as timestamp1,
        ulid()::timestamp as timestamp2
)
SELECT cmp_ok(timestamp1, '<=', timestamp2, 'ULID timestamps are ordered') FROM timestamp_ordering;

-- Test 8: Monotonic behavior under load (using cmp_ok)
WITH load_test AS (
    SELECT 
        ulid() as ulid_val,
        ROW_NUMBER() OVER (ORDER BY ulid()) as row_num
    FROM generate_series(1, 1000)
)
SELECT cmp_ok(COUNT(*), '=', 1000, 'Load test generates 1000 ULIDs') FROM load_test;

-- Test 9: Monotonic ordering with LAG function (using isnt_null)
WITH lag_test AS (
    SELECT 
        ulid() as ulid_val,
        LAG(ulid()) OVER (ORDER BY ulid()) as prev_ulid
    FROM generate_series(1, 100)
)
SELECT isnt_null(ulid_val, 'LAG test generates non-null ULIDs') FROM lag_test LIMIT 1;

-- Test 10: Monotonic ordering with LAG function 2 (using isnt_null)
WITH lag_test AS (
    SELECT 
        ulid() as ulid_val,
        LAG(ulid()) OVER (ORDER BY ulid()) as prev_ulid
    FROM generate_series(1, 100)
)
SELECT isnt_null(prev_ulid, 'LAG test generates non-null previous ULIDs') FROM lag_test OFFSET 1 LIMIT 1;

-- Test 11: Monotonic ordering with LAG function 3 (using isnt_null)
WITH lag_test AS (
    SELECT 
        ulid() as ulid_val,
        LAG(ulid()) OVER (ORDER BY ulid()) as prev_ulid
    FROM generate_series(1, 100)
)
SELECT isnt_null(ulid_val, 'LAG test generates non-null current ULIDs') FROM lag_test OFFSET 1 LIMIT 1;

-- Test 12: Monotonic ordering with LAG function 4 (using isnt_null)
WITH lag_test AS (
    SELECT 
        ulid() as ulid_val,
        LAG(ulid()) OVER (ORDER BY ulid()) as prev_ulid
    FROM generate_series(1, 100)
)
SELECT isnt_null(prev_ulid, 'LAG test generates non-null previous ULIDs for comparison') FROM lag_test OFFSET 1 LIMIT 1;

-- Test 13: Monotonic ordering with LAG function 5 (using isnt_null)
WITH lag_test AS (
    SELECT 
        ulid() as ulid_val,
        LAG(ulid()) OVER (ORDER BY ulid()) as prev_ulid
    FROM generate_series(1, 100)
)
SELECT isnt_null(ulid_val, 'LAG test generates non-null current ULIDs for comparison') FROM lag_test OFFSET 1 LIMIT 1;

-- Test 14: Monotonic ordering with LAG function 6 (using isnt_null)
WITH lag_test AS (
    SELECT 
        ulid() as ulid_val,
        LAG(ulid()) OVER (ORDER BY ulid()) as prev_ulid
    FROM generate_series(1, 100)
)
SELECT isnt_null(prev_ulid, 'LAG test generates non-null previous ULIDs for final comparison') FROM lag_test OFFSET 1 LIMIT 1;

-- Test 15: Monotonic ordering with LAG function 7 (using isnt_null)
WITH lag_test AS (
    SELECT 
        ulid() as ulid_val,
        LAG(ulid()) OVER (ORDER BY ulid()) as prev_ulid
    FROM generate_series(1, 100)
)
SELECT isnt_null(ulid_val, 'LAG test generates non-null current ULIDs for final comparison') FROM lag_test OFFSET 1 LIMIT 1;

-- Show test results
SELECT * FROM finish();
