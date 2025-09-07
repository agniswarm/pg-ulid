-- pgTAP Binary Storage Tests
-- Tests that ULIDs are stored as binary on disk with diverse pgTAP assertions

-- Load the custom pgTAP functions
\i test/sql/pgtap_functions.sql

-- Start test plan
SELECT plan(15);

-- Test 1: Create test table (using isnt_null)
CREATE TEMP TABLE storage_test (
    id ulid DEFAULT ulid(),
    name text
);

SELECT isnt_null(id, 'Test table created with ULID column') FROM storage_test LIMIT 1;

-- Test 2: Insert test data (using is)
INSERT INTO storage_test (name) VALUES ('test1'), ('test2'), ('test3');

SELECT is(COUNT(*), 3, 'Test data inserted successfully') FROM storage_test;

-- Test 3: Text length verification (using is)
WITH length_test AS (
    SELECT 
        ulid() as ulid_val,
        length(ulid()::text) as text_length
)
SELECT is(text_length, 25, 'ULID text representation is 25 characters') FROM length_test;

-- Test 4: Binary length verification (using is)
WITH binary_test AS (
    SELECT 
        ulid() as ulid_val,
        octet_length(ulid()::text) as text_bytes,
        octet_length(ulid()::bytea) as binary_bytes
)
SELECT is(binary_bytes, 16, 'ULID binary representation is 16 bytes') FROM binary_test;

-- Test 5: Storage efficiency test (using cmp_ok)
WITH efficiency_test AS (
    SELECT 
        octet_length(ulid()::text) as text_bytes,
        octet_length(ulid()::bytea) as binary_bytes
)
SELECT cmp_ok(binary_bytes, '<', text_bytes, 'Binary storage is more efficient than text') FROM efficiency_test;

-- Test 6: Storage efficiency percentage (using cmp_ok)
WITH efficiency_test AS (
    SELECT 
        octet_length(ulid()::text) as text_bytes,
        octet_length(ulid()::bytea) as binary_bytes,
        ROUND((octet_length(ulid()::bytea)::float / octet_length(ulid()::text)::float) * 100, 2) as efficiency_percent
)
SELECT cmp_ok(efficiency_percent, '<', 70, 'Binary storage is at least 30% more efficient') FROM efficiency_test;

-- Test 7: System table verification (using isnt_null)
WITH system_check AS (
    SELECT 
        t.typname as type_name,
        t.typlen as type_length,
        t.typalign as type_align
    FROM pg_type t
    WHERE t.typname = 'ulid'
)
SELECT isnt_null(type_name, 'ULID type exists in system tables') FROM system_check;

-- Test 8: System table length verification (using is)
WITH system_check AS (
    SELECT 
        t.typname as type_name,
        t.typlen as type_length,
        t.typalign as type_align
    FROM pg_type t
    WHERE t.typname = 'ulid'
)
SELECT is(type_length, 16, 'ULID type length is 16 bytes in system tables') FROM system_check;

-- Test 9: System table alignment verification (using is)
WITH system_check AS (
    SELECT 
        t.typname as type_name,
        t.typlen as type_length,
        t.typalign as type_align
    FROM pg_type t
    WHERE t.typname = 'ulid'
)
SELECT is(type_align, 'c', 'ULID type alignment is char in system tables') FROM system_check;

-- Test 10: Binary round-trip test (using is)
WITH round_trip_test AS (
    SELECT 
        ulid() as original_ulid,
        ulid()::bytea::ulid as round_trip_ulid
)
SELECT is(original_ulid, round_trip_ulid, 'Binary round-trip preserves ULID value') FROM round_trip_test;

-- Test 11: Binary round-trip test 2 (using is)
WITH round_trip_test AS (
    SELECT 
        ulid() as original_ulid,
        ulid()::bytea::ulid as round_trip_ulid
)
SELECT is(original_ulid, round_trip_ulid, 'Binary round-trip preserves ULID value 2') FROM round_trip_test;

-- Test 12: Binary round-trip test 3 (using is)
WITH round_trip_test AS (
    SELECT 
        ulid() as original_ulid,
        ulid()::bytea::ulid as round_trip_ulid
)
SELECT is(original_ulid, round_trip_ulid, 'Binary round-trip preserves ULID value 3') FROM round_trip_test;

-- Test 13: Binary round-trip test 4 (using is)
WITH round_trip_test AS (
    SELECT 
        ulid() as original_ulid,
        ulid()::bytea::ulid as round_trip_ulid
)
SELECT is(original_ulid, round_trip_ulid, 'Binary round-trip preserves ULID value 4') FROM round_trip_test;

-- Test 14: Binary round-trip test 5 (using is)
WITH round_trip_test AS (
    SELECT 
        ulid() as original_ulid,
        ulid()::bytea::ulid as round_trip_ulid
)
SELECT is(original_ulid, round_trip_ulid, 'Binary round-trip preserves ULID value 5') FROM round_trip_test;

-- Test 15: Comprehensive binary storage test (using ok as last resort)
WITH comprehensive_test AS (
    SELECT 
        octet_length(ulid()::bytea) = 16 as binary_length_correct,
        octet_length(ulid()::text) = 25 as text_length_correct,
        ulid()::bytea::ulid = ulid() as round_trip_works
)
SELECT ok(binary_length_correct AND text_length_correct AND round_trip_works, 'Comprehensive binary storage test passes') FROM comprehensive_test;

-- Clean up
DROP TABLE IF EXISTS storage_test;

-- Show test results
SELECT * FROM finish();
