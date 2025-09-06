#!/bin/bash

# Standalone PostgreSQL Extension Test Script
# This can be run without the Makefile and PostgreSQL build system

echo "Running PostgreSQL extension tests..."

# Check if PostgreSQL is running
if ! pg_isready -q; then
    echo "PostgreSQL is not running. This test requires a running PostgreSQL instance."
    echo "In CI, PostgreSQL should be started by the CI environment."
    echo "Locally, start PostgreSQL with: sudo service postgresql start"
    exit 1
fi

# Use the default postgres database
export PGDATABASE=postgres

# Test basic extension functionality
echo "Creating extension..."
if ! psql -c "CREATE EXTENSION IF NOT EXISTS ulid;"; then
    echo "ERROR: Failed to create extension. Make sure it's properly installed."
    echo "Check that the extension files are in the correct location:"
    echo "  - /usr/share/postgresql/*/extension/ulid.control"
    echo "  - /usr/share/postgresql/*/extension/ulid--1.0.0.sql"
    exit 1
fi

echo "Testing ulid() function..."
if ! psql -c "SELECT ulid();"; then
    echo "ERROR: ulid() function test failed"
    exit 1
fi

echo "Testing ulid_random() function..."
if ! psql -c "SELECT ulid_random();"; then
    echo "ERROR: ulid_random() function test failed"
    exit 1
fi

echo "Testing ulid_time() function..."
if ! psql -c "SELECT ulid_time(extract(epoch from now()) * 1000::BIGINT);"; then
    echo "ERROR: ulid_time() function test failed"
    exit 1
fi

echo "Testing ulid_batch() function..."
if ! psql -c "SELECT array_length(ulid_batch(5), 1);"; then
    echo "ERROR: ulid_batch() function test failed"
    exit 1
fi

echo "Testing ulid_random_batch() function..."
if ! psql -c "SELECT array_length(ulid_random_batch(3), 1);"; then
    echo "ERROR: ulid_random_batch() function test failed"
    exit 1
fi

echo "Testing ulid_parse() function..."
if ! psql -c "SELECT * FROM ulid_parse('01K4FQ7QN4ZSW0SG5XACGM2HB4');"; then
    echo "ERROR: ulid_parse() function test failed"
    exit 1
fi

echo "Testing error handling..."
psql -c "SELECT ulid_parse('invalid-ulid');" || echo "Expected error for invalid ULID"

echo "Testing batch with zero count..."
psql -c "SELECT ulid_batch(0);"

echo "Testing batch with negative count..."
psql -c "SELECT ulid_batch(-1);" || echo "Expected error for negative count"

echo "Cleaning up..."
psql -c "DROP EXTENSION IF EXISTS ulid;"

echo "All tests passed successfully!"
