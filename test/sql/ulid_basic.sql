-- Test basic ULID functionality
CREATE EXTENSION IF NOT EXISTS ulid;

-- Test ULID generation
SELECT ulid_generate() IS NOT NULL AS ulid_generated;

-- Test ULID with timestamp
SELECT ulid_generate_with_timestamp(extract(epoch from now())::bigint) IS NOT NULL AS ulid_with_timestamp;

-- Test ULID parsing
SELECT ulid_parse('01ARZ3NDEKTSV4RRFFQ69G5FAV') IS NOT NULL AS ulid_parsed;

-- Test ULID timestamp extraction
SELECT ulid_timestamp(ulid_generate()) IS NOT NULL AS ulid_timestamp;

-- Test ULID comparison
SELECT ulid_generate() < ulid_generate() AS ulid_comparison;

-- Test ULID casting
SELECT ulid_generate()::text IS NOT NULL AS ulid_to_text;
SELECT '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid IS NOT NULL AS text_to_ulid;
