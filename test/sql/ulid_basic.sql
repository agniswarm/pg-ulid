-- Test basic ULID functionality
CREATE EXTENSION IF NOT EXISTS ulid;

-- Test ulid() function
SELECT ulid() IS NOT NULL AS ulid_generated;

-- Test ulid_random() function
SELECT ulid_random() IS NOT NULL AS ulid_random_generated;

-- Test ulid_time() function
SELECT ulid_time((extract(epoch from now()) * 1000)::BIGINT) IS NOT NULL AS ulid_time_generated;

-- Test ulid_batch() function
SELECT array_length(ulid_batch(5), 1) = 5 AS ulid_batch_test;

-- Test ulid_random_batch() function
SELECT array_length(ulid_random_batch(3), 1) = 3 AS ulid_random_batch_test;

-- Test ulid_parse() function
SELECT * FROM ulid_parse('01K4FQ7QN4ZSW0SG5XACGM2HB4') IS NOT NULL AS ulid_parse_test;
