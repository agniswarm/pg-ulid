# ULID Extension Test Suite

This directory contains comprehensive test files for the PostgreSQL ULID extension, organized by functionality and test context.

## Test Files Overview

### 01_basic_functionality.sql

Tests core ULID generation, parsing, and basic operations:

- `ulid()` function (monotonic by default)
- `ulid_random()` function
- `ulid_crypto()` function
- `ulid_time()` function
- `ulid_parse()` function
- Batch generation functions

### 02_casting_operations.sql

Tests all casting operations between ULID, text, timestamp, and UUID:

- Text to/from ULID casting
- Timestamp to/from ULID casting
- Timestamptz to/from ULID casting
- UUID to/from ULID casting
- Range queries with casting

### 03_monotonic_generation.sql

Tests monotonic behavior and ordering of ULIDs:

- Basic monotonic generation
- Monotonic ordering verification
- Rapid generation monotonicity
- Ordering consistency checks

### 04_stress_tests.sql

Tests performance and correctness under high load:

- Small scale stress test (1,000 ULIDs)
- Medium scale stress test (10,000 ULIDs)
- Large scale stress test (100,000 ULIDs)
- Very large scale stress test (1,000,000 ULIDs)
- Extreme scale stress test (10,000,000 ULIDs)
- Performance timing tests

### 05_binary_storage.sql

Tests that ULIDs are stored as binary on disk:

- Binary storage verification
- Storage efficiency comparison
- Binary data structure verification
- PostgreSQL system tables confirmation
- Binary round-trip verification

### 06_database_operations.sql

Tests ULID usage in real database scenarios:

- Primary key usage
- Foreign key relationships
- Indexing and querying
- Sorting and ordering
- Aggregation functions
- Timestamp extraction
- UUID conversion

### 07_error_handling.sql

Tests error conditions and edge cases:

- Invalid ULID format handling
- Invalid timestamp casting
- NULL handling
- Edge case timestamps
- Boundary conditions
- Function parameter validation
- Type compatibility errors

### 08_readme_functionality.sql

Tests all functions and features documented in README.md:

- All documented generation functions
- All casting operations
- Database operations
- Range queries
- Performance features
- Binary storage verification

### 09_comprehensive_test.sql

Runs all tests in sequence to verify complete functionality:

- Extension installation verification
- All documented functions
- All casting operations
- Monotonic generation
- Binary storage
- Database operations
- Performance tests
- Error handling
- Final verification

## pgTAP-Style Testing Framework

### pgtap_functions.sql

Custom pgTAP-like testing framework providing:

- `plan(n)` - Declare number of tests
- `ok(condition, test_name, message)` - Assert condition is true
- `is(got, expected, test_name, message)` - Assert equality
- `finish()` - Show test results summary
- Proper test result tracking and reporting

### 11_pgtap_basic_tests.sql

pgTAP-style basic functionality tests with proper assertions:

- Basic ULID generation
- Format validation
- Uniqueness verification
- Function availability
- Casting operations
- Binary storage verification

### 12_pgtap_stress_tests.sql

pgTAP-style stress tests with proper assertions:

- Uniqueness at scale (1K, 10K, 100K, 1M ULIDs)
- Monotonic ordering verification
- Performance timing tests
- Memory usage analysis
- Storage efficiency verification

### 13_pgtap_error_tests.sql

pgTAP-style error handling tests with proper assertions:

- Invalid input format handling
- Error condition verification
- Edge case testing
- Boundary condition validation

### 14_pgtap_comprehensive.sql

Complete pgTAP test suite covering all functionality:

- All basic functions
- All casting operations
- Monotonic generation
- Stress testing
- Error handling
- Performance verification

### 15_pgtap_simple.sql

Simplified pgTAP test suite focusing on core functionality:

- Essential function tests
- Basic validation
- Error handling
- Performance checks

### 16_pgtap_final.sql

Final working pgTAP test suite:

- Core functionality verification
- Proper assertion handling
- Test result reporting
- Summary statistics

## Running the Tests

### Individual Test Files

```bash
# Run a specific test file
docker exec -it pg-ulid-test psql -U postgres -d testdb -f /path/to/test/sql/01_basic_functionality.sql
```

### All Tests

```bash
# Run all tests in sequence
for test_file in test/sql/*.sql; do
    echo "Running $test_file..."
    docker exec -it pg-ulid-test psql -U postgres -d testdb -f "$test_file"
done
```

### Comprehensive Test

```bash
# Run the comprehensive test suite
docker exec -it pg-ulid-test psql -U postgres -d testdb -f test/sql/09_comprehensive_test.sql
```

## Test Categories

### ✅ **Core Functionality Tests**

- Basic ULID generation
- Parsing and conversion
- Batch operations
- All documented functions

### ✅ **Casting Tests**

- Text casting
- Timestamp casting
- UUID casting
- Range queries

### ✅ **Monotonic Tests**

- Ordering verification
- Uniqueness checks
- Rapid generation tests

### ✅ **Performance Tests**

- Stress testing (1K, 10K, 100K ULIDs)
- Timing measurements
- Load testing

### ✅ **Storage Tests**

- Binary storage verification
- Space efficiency analysis
- Data structure validation

### ✅ **Database Tests**

- Table operations
- Indexing
- Querying
- Relationships

### ✅ **Error Handling Tests**

- Invalid input handling
- Edge cases
- Boundary conditions
- Type validation

## Expected Results

All tests should pass with:

- ✅ All ULIDs generated successfully
- ✅ All casting operations working
- ✅ Monotonic ordering maintained
- ✅ Binary storage confirmed
- ✅ Database operations functional
- ✅ Error handling working correctly
- ✅ Performance within acceptable limits

## Notes

- Tests are designed to be run in a Docker container with the ULID extension installed
- Some tests may take longer to run (especially stress tests)
- Tests clean up after themselves where possible
- All tests include verification messages for easy debugging
