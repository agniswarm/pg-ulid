#!/bin/bash

# Comprehensive PostgreSQL Extension Test Script
# Runs the full SQL test suite from test/sql/ directory

echo "Running comprehensive PostgreSQL extension tests..."

# Check if PostgreSQL is running
if ! pg_isready -q; then
    echo "PostgreSQL is not running. This test requires a running PostgreSQL instance."
    echo "In CI, PostgreSQL should be started by the CI environment."
    echo "Locally, start PostgreSQL with: sudo service postgresql start"
    exit 1
fi

# Use the default postgres database
export PGDATABASE=postgres

# Create test database
echo "Creating test database..."
if ! psql -c "CREATE DATABASE testdb;"; then
    echo "WARNING: testdb already exists or creation failed, continuing..."
fi

# Switch to test database
export PGDATABASE=testdb

# Test basic extension functionality
echo "Creating extension..."
if ! psql -c "CREATE EXTENSION IF NOT EXISTS ulid;"; then
    echo "ERROR: Failed to create extension. Make sure it's properly installed."
    echo "Check that the extension files are in the correct location:"
    echo "  - /usr/share/postgresql/*/extension/ulid.control"
    echo "  - /usr/share/postgresql/*/extension/ulid--0.1.1.sql"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
SQL_TEST_DIR="$PROJECT_ROOT/test/sql"

# Check if SQL test directory exists
if [ ! -d "$SQL_TEST_DIR" ]; then
    echo "ERROR: SQL test directory not found: $SQL_TEST_DIR"
    exit 1
fi

# Load pgTAP functions first
echo "Loading pgTAP functions..."
if ! psql -f "$SQL_TEST_DIR/pgtap_functions.sql"; then
    echo "ERROR: Failed to load pgTAP functions"
    exit 1
fi

# Run all SQL test files
echo "Running comprehensive SQL tests..."
TEST_FILES=(
    "01_basic_functionality.sql"
    "02_casting_operations.sql"
    "03_monotonic_generation.sql"
    "04_stress_tests.sql"
    "05_binary_storage.sql"
    "06_database_operations.sql"
    "07_error_handling.sql"
)

FAILED_TESTS=0

for test_file in "${TEST_FILES[@]}"; do
    test_path="$SQL_TEST_DIR/$test_file"
    if [ -f "$test_path" ]; then
        echo "Running $test_file..."
        if ! psql -f "$test_path"; then
            echo "ERROR: Test $test_file failed"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        else
            echo "✅ $test_file passed"
        fi
    else
        echo "WARNING: Test file $test_file not found, skipping"
    fi
done

# Clean up
echo "Cleaning up..."
psql -c "DROP EXTENSION IF EXISTS ulid;" || true
psql -c "DROP DATABASE IF EXISTS testdb;" || true

# Report results
if [ $FAILED_TESTS -eq 0 ]; then
    echo "🎉 All tests passed successfully!"
    exit 0
else
    echo "❌ $FAILED_TESTS test(s) failed"
    exit 1
fi
