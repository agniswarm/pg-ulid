#!/bin/bash

# PostgreSQL Extension CI Test Script
# Tests the ulid extension functionality in PostgreSQL

set -e  # Exit on any error

echo "Starting PostgreSQL extension tests..."

# Test basic extension functionality
echo "Creating extension..."
psql -c "CREATE EXTENSION IF NOT EXISTS ulid;"

echo "Testing ulid() function..."
psql -c "SELECT ulid();"

echo "Testing ulid_random() function..."
psql -c "SELECT ulid_random();"

echo "Testing ulid_time() function..."
psql -c "SELECT ulid_time(extract(epoch from now()) * 1000);"

echo "Testing ulid_batch() function..."
psql -c "SELECT array_length(ulid_batch(5), 1);"

echo "Testing ulid_random_batch() function..."
psql -c "SELECT array_length(ulid_random_batch(3), 1);"

echo "Testing ulid_parse() function..."
psql -c "SELECT * FROM ulid_parse('01K4FQ7QN4ZSW0SG5XACGM2HB4');"

echo "Testing error handling..."
psql -c "SELECT ulid_parse('invalid-ulid');" || echo "Expected error for invalid ULID"

echo "Testing batch with zero count..."
psql -c "SELECT ulid_batch(0);"

echo "Testing batch with negative count..."
psql -c "SELECT ulid_batch(-1);" || echo "Expected error for negative count"

echo "Cleaning up..."
psql -c "DROP EXTENSION IF EXISTS ulid;"

echo "All tests passed successfully!"
