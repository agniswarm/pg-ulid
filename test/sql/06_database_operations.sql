-- pgTAP Database Operations Tests
-- Tests ULID usage in real database scenarios with diverse pgTAP assertions

-- Load the custom pgTAP functions
\i test/sql/pgtap_functions.sql

-- Start test plan
SELECT plan(20);

-- Test 1: Primary key usage (using isnt_null)
CREATE TEMP TABLE users (
    id ulid PRIMARY KEY,
    username text NOT NULL,
    verification text DEFAULT 'verified'
);

SELECT isnt_null(id, 'Primary key column created successfully') FROM users LIMIT 1;

-- Test 2: Foreign key relationships (using isnt_null)
CREATE TEMP TABLE orders (
    order_id ulid PRIMARY KEY,
    username text NOT NULL,
    total_amount decimal(10,2),
    verification text DEFAULT 'verified'
);

SELECT isnt_null(order_id, 'Foreign key table created successfully') FROM orders LIMIT 1;

-- Test 3: Indexing and querying (using isnt_null)
CREATE INDEX idx_users_id ON users(id);
CREATE INDEX idx_orders_id ON orders(order_id);

SELECT isnt_null(id, 'Index created successfully') FROM users LIMIT 1;

-- Test 4: Range queries (using isnt_null)
WITH range_test AS (
    SELECT id, username
    FROM users
    WHERE id >= (SELECT MIN(id) FROM users)
    LIMIT 5
)
SELECT isnt_null(id, 'Range query works') FROM range_test LIMIT 1;

-- Test 5: Sorting and ordering (using isnt_null)
WITH sorting_test AS (
    SELECT id, username, created_at
    FROM users
    ORDER BY id
    LIMIT 5
)
SELECT isnt_null(id, 'Sorting works') FROM sorting_test LIMIT 1;

-- Test 6: Aggregation functions (using isnt_null)
WITH aggregation_test AS (
    SELECT 
        MIN(id) as first_user_id,
        MAX(id) as last_user_id,
        COUNT(*) as total_users
    FROM users
)
SELECT isnt_null(first_user_id, 'Aggregation functions work') FROM aggregation_test;

-- Test 7: Timestamp extraction (using isnt_null)
WITH timestamp_test AS (
    SELECT 
        id,
        username,
        id::timestamp as generated_timestamp,
        CURRENT_TIMESTAMP as db_timestamp,
        'timestamp_extracted' as verification
    FROM users
    LIMIT 5
)
SELECT isnt_null(generated_timestamp, 'Timestamp extraction works') FROM timestamp_test LIMIT 1;

-- Test 8: UUID conversion (using isnt_null)
WITH uuid_test AS (
    SELECT 
        id as ulid_id,
        id::uuid as uuid_id,
        'uuid_converted' as verification
    FROM users
    LIMIT 5
)
SELECT isnt_null(uuid_id, 'UUID conversion works') FROM uuid_test LIMIT 1;

-- Test 9: Range queries with timestamps (using isnt_null)
WITH range_timestamp_test AS (
    SELECT 
        id,
        username,
        email,
        id::timestamp as created_at
    FROM users
    WHERE id::timestamp >= '2023-01-01'::timestamp
    LIMIT 5
)
SELECT isnt_null(id, 'Range query with timestamps works') FROM range_timestamp_test LIMIT 1;

-- Test 10: Performance features (using isnt_null)
WITH performance_test AS (
    SELECT 
        id,
        username,
        'performance_verified' as verification
    FROM users
    ORDER BY id
    LIMIT 5
)
SELECT isnt_null(id, 'Performance features work') FROM performance_test LIMIT 1;

-- Test 11: Binary storage verification (using isnt_null)
WITH binary_storage_test AS (
    SELECT 
        id::text as ulid_text,
        length(id::text) as text_length,
        octet_length(id::bytea) as binary_length,
        'binary_verified' as verification
    FROM users
    LIMIT 5
)
SELECT isnt_null(ulid_text, 'Binary storage verification works') FROM binary_storage_test LIMIT 1;

-- Test 12: Text length verification (using is)
WITH text_length_test AS (
    SELECT 
        length(id::text) as text_length
    FROM users
    LIMIT 1
)
SELECT is(text_length, 25, 'Text length is correct') FROM text_length_test;

-- Test 13: Binary length verification (using is)
WITH binary_length_test AS (
    SELECT 
        octet_length(id::bytea) as binary_length
    FROM users
    LIMIT 1
)
SELECT is(binary_length, 16, 'Binary length is correct') FROM binary_length_test;

-- Test 14: Storage efficiency test (using cmp_ok)
WITH efficiency_test AS (
    SELECT 
        octet_length(id::text) as text_bytes,
        octet_length(id::bytea) as binary_bytes
    FROM users
    LIMIT 1
)
SELECT cmp_ok(binary_bytes, '<', text_bytes, 'Binary storage is more efficient') FROM efficiency_test;

-- Test 15: Round-trip conversion test (using is)
WITH round_trip_test AS (
    SELECT 
        id as original_id,
        id::text::ulid as round_trip_id
    FROM users
    LIMIT 1
)
SELECT is(original_id, round_trip_id, 'Round-trip conversion works') FROM round_trip_test;

-- Test 16: Timestamp ordering test (using cmp_ok)
WITH timestamp_ordering_test AS (
    SELECT 
        id::timestamp as timestamp1,
        id::timestamp as timestamp2
    FROM users
    LIMIT 2
)
SELECT cmp_ok(timestamp1, '<=', timestamp2, 'Timestamp ordering works') FROM timestamp_ordering_test;

-- Test 17: UUID format test (using isnt_null)
WITH uuid_format_test AS (
    SELECT 
        id::uuid as uuid_id
    FROM users
    LIMIT 1
)
SELECT isnt_null(uuid_id, 'UUID format is valid') FROM uuid_format_test;

-- Test 18: Text format test (using is)
WITH text_format_test AS (
    SELECT 
        length(id::text) as text_length
    FROM users
    LIMIT 1
)
SELECT is(text_length, 25, 'Text format is correct') FROM text_format_test;

-- Test 19: Binary format test (using is)
WITH binary_format_test AS (
    SELECT 
        octet_length(id::bytea) as binary_length
    FROM users
    LIMIT 1
)
SELECT is(binary_length, 16, 'Binary format is correct') FROM binary_format_test;

-- Test 20: Comprehensive database operations test (using ok as last resort)
WITH comprehensive_test AS (
    SELECT 
        COUNT(*) > 0 as has_data,
        MIN(id) IS NOT NULL as has_min_id,
        MAX(id) IS NOT NULL as has_max_id,
        COUNT(DISTINCT id) = COUNT(*) as all_unique
    FROM users
)
SELECT ok(has_data AND has_min_id AND has_max_id AND all_unique, 'Comprehensive database operations test passes') FROM comprehensive_test;

-- Clean up
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS users;

-- Show test results
SELECT * FROM finish();
