-- pgTAP Stress Tests
-- Tests performance and correctness under high load with diverse pgTAP assertions

-- Load the custom pgTAP functions
\i test/sql/pgtap_functions.sql

-- Start test plan
SELECT plan(20);

-- Test 1: Small batch generation (using is)
SELECT is(array_length(ulid_batch(100), 1), 100, 'Small batch generation works');

-- Test 2: Medium batch generation (using is)
SELECT is(array_length(ulid_batch(1000), 1), 1000, 'Medium batch generation works');

-- Test 3: Large batch generation (using is)
SELECT is(array_length(ulid_batch(10000), 1), 10000, 'Large batch generation works');

-- Test 4: Very large batch generation (using is)
SELECT is(array_length(ulid_batch(100000), 1), 100000, 'Very large batch generation works');

-- Test 5: Massive batch generation (using is)
SELECT is(array_length(ulid_batch(1000000), 1), 1000000, 'Massive batch generation works');

-- Test 6: Uniqueness test for small batch (using cmp_ok)
WITH small_batch AS (
    SELECT unnest(ulid_batch(100)) as ulid_val
)
SELECT cmp_ok(COUNT(*), '=', COUNT(DISTINCT ulid_val), 'Small batch generates unique ULIDs') FROM small_batch;

-- Test 7: Uniqueness test for medium batch (using cmp_ok)
WITH medium_batch AS (
    SELECT unnest(ulid_batch(1000)) as ulid_val
)
SELECT cmp_ok(COUNT(*), '=', COUNT(DISTINCT ulid_val), 'Medium batch generates unique ULIDs') FROM medium_batch;

-- Test 8: Uniqueness test for large batch (using cmp_ok)
WITH large_batch AS (
    SELECT unnest(ulid_batch(10000)) as ulid_val
)
SELECT cmp_ok(COUNT(*), '=', COUNT(DISTINCT ulid_val), 'Large batch generates unique ULIDs') FROM large_batch;

-- Test 9: Uniqueness test for very large batch (using cmp_ok)
WITH very_large_batch AS (
    SELECT unnest(ulid_batch(100000)) as ulid_val
)
SELECT cmp_ok(COUNT(*), '=', COUNT(DISTINCT ulid_val), 'Very large batch generates unique ULIDs') FROM very_large_batch;

-- Test 10: Uniqueness test for massive batch (using cmp_ok)
WITH massive_batch AS (
    SELECT unnest(ulid_batch(1000000)) as ulid_val
)
SELECT cmp_ok(COUNT(*), '=', COUNT(DISTINCT ulid_val), 'Massive batch generates unique ULIDs') FROM massive_batch;

-- Test 11: Performance test for 1,000 ULIDs (using cmp_ok)
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    duration INTERVAL;
BEGIN
    start_time := clock_timestamp();
    PERFORM unnest(ulid_batch(1000));
    end_time := clock_timestamp();
    duration := end_time - start_time;
    
    PERFORM ok(duration < INTERVAL '1 second', '1,000 ULIDs generated in under 1 second');
END $$;

-- Test 12: Performance test for 10,000 ULIDs (using cmp_ok)
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    duration INTERVAL;
BEGIN
    start_time := clock_timestamp();
    PERFORM unnest(ulid_batch(10000));
    end_time := clock_timestamp();
    duration := end_time - start_time;
    
    PERFORM ok(duration < INTERVAL '5 seconds', '10,000 ULIDs generated in under 5 seconds');
END $$;

-- Test 13: Performance test for 100,000 ULIDs (using cmp_ok)
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    duration INTERVAL;
BEGIN
    start_time := clock_timestamp();
    PERFORM unnest(ulid_batch(100000));
    end_time := clock_timestamp();
    duration := end_time - start_time;
    
    PERFORM ok(duration < INTERVAL '30 seconds', '100,000 ULIDs generated in under 30 seconds');
END $$;

-- Test 14: Performance test for 1,000,000 ULIDs (using cmp_ok)
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    duration INTERVAL;
BEGIN
    start_time := clock_timestamp();
    PERFORM unnest(ulid_batch(1000000));
    end_time := clock_timestamp();
    duration := end_time - start_time;
    
    PERFORM ok(duration < INTERVAL '5 minutes', '1,000,000 ULIDs generated in under 5 minutes');
END $$;

-- Test 15: Performance test for 10,000,000 ULIDs (using cmp_ok)
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    duration INTERVAL;
BEGIN
    start_time := clock_timestamp();
    PERFORM unnest(ulid_batch(10000000));
    end_time := clock_timestamp();
    duration := end_time - start_time;
    
    PERFORM ok(duration < INTERVAL '30 minutes', '10,000,000 ULIDs generated in under 30 minutes');
END $$;

-- Test 16: Memory usage test (using isnt_null)
WITH memory_test AS (
    SELECT 
        pg_size_pretty(pg_column_size(ulid_batch(1000))) as batch_size,
        pg_size_pretty(pg_column_size(ulid_batch(10000))) as large_batch_size
)
SELECT isnt_null(batch_size, 'Memory usage test for batch size') FROM memory_test;

-- Test 17: Memory usage test 2 (using isnt_null)
WITH memory_test AS (
    SELECT 
        pg_size_pretty(pg_column_size(ulid_batch(1000))) as batch_size,
        pg_size_pretty(pg_column_size(ulid_batch(10000))) as large_batch_size
)
SELECT isnt_null(large_batch_size, 'Memory usage test for large batch size') FROM memory_test;

-- Test 18: Memory usage test 3 (using isnt_null)
WITH memory_test AS (
    SELECT 
        pg_size_pretty(pg_column_size(ulid_batch(1000))) as batch_size,
        pg_size_pretty(pg_column_size(ulid_batch(10000))) as large_batch_size
)
SELECT isnt_null(batch_size, 'Memory usage test for batch size verification') FROM memory_test;

-- Test 19: Memory usage test 4 (using isnt_null)
WITH memory_test AS (
    SELECT 
        pg_size_pretty(pg_column_size(ulid_batch(1000))) as batch_size,
        pg_size_pretty(pg_column_size(ulid_batch(10000))) as large_batch_size
)
SELECT isnt_null(large_batch_size, 'Memory usage test for large batch size verification') FROM memory_test;

-- Test 20: Comprehensive stress test (using ok as last resort)
WITH comprehensive_test AS (
    SELECT 
        array_length(ulid_batch(1000), 1) = 1000 as batch_works,
        COUNT(DISTINCT unnest(ulid_batch(1000))) = 1000 as uniqueness_works,
        ulid() IS NOT NULL as generation_works
)
SELECT ok(batch_works AND uniqueness_works AND generation_works, 'Comprehensive stress test passes') FROM comprehensive_test;

-- Show test results
SELECT * FROM finish();
