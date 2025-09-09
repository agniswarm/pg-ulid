# ULID Extension Python Tests

This directory contains comprehensive Python tests for the PostgreSQL ULID extension using pytest. These tests provide better validation than SQL tests and can catch more edge cases with proper assertions and error handling.

## Test Files

- `test_01_basic_functionality.py` - Tests basic ULID generation, validation, and core functionality
- `test_02_casting_operations.py` - Tests all ULID casting operations between different types
- `test_03_monotonic_generation.py` - Tests ULID monotonic generation and ordering properties
- `test_04_stress_tests.py` - Tests ULID generation under various stress conditions
- `test_05_binary_storage.py` - Tests ULID binary storage and efficiency
- `test_06_database_operations.py` - Tests database operations with ULID columns
- `test_07_error_handling.py` - Tests error handling and edge cases

## Prerequisites

1. **Python 3.8+** with pytest installed:

   ```bash
   pip install pytest psycopg2-binary
   ```

2. **PostgreSQL** with the ULID extension installed:

   ```bash
   # Install the extension (see main README for build instructions)
   psql -d testdb -c "CREATE EXTENSION ulid;"
   ```

## Environment Setup

Set the following environment variables for database connection:

```bash
export PGHOST=localhost
export PGDATABASE=testdb
export PGUSER=postgres
export PGPASSWORD=your_password
export PGPORT=5432
```

## Running Tests

### Run All Tests

```bash
# From the project root
python -m pytest test/python/ -v

# Or from the test directory
cd test/python
python -m pytest -v
```

### Run Individual Test Files

```bash
# Basic functionality tests
python -m pytest test/python/test_01_basic_functionality.py -v

# Casting operations tests
python -m pytest test/python/test_02_casting_operations.py -v

# Monotonic generation tests
python -m pytest test/python/test_03_monotonic_generation.py -v

# Stress tests
python -m pytest test/python/test_04_stress_tests.py -v

# Binary storage tests
python -m pytest test/python/test_05_binary_storage.py -v

# Database operations tests
python -m pytest test/python/test_06_database_operations.py -v

# Error handling tests
python -m pytest test/python/test_07_error_handling.py -v
```

### Run Specific Tests

```bash
# Run a specific test function
python -m pytest test/python/test_01_basic_functionality.py::test_basic_generation_and_lengths -v

# Run tests matching a pattern
python -m pytest test/python/ -k "casting" -v
```

## Test Features

- **Comprehensive Coverage**: Tests all documented functionality and edge cases
- **Real Assertions**: Uses Python assertions with detailed error messages
- **Performance Testing**: Includes timing and stress tests with configurable limits
- **Error Handling**: Proper exception handling and error message validation
- **Cleanup**: Automatic cleanup of test data and proper transaction handling
- **Detailed Output**: Clear pass/fail reporting with timing information
- **Skip Logic**: Intelligent skipping of tests when functions are not available

## Test Categories

### Basic Functionality (test_01)

- ULID generation functions (`ulid()`, `ulid_random()`)
- Uniqueness validation across multiple generations
- Length validation (26 characters)
- Batch operations (`ulid_batch()`, `ulid_random_batch()`)
- NULL handling and edge cases
- README functionality validation

### Casting Operations (test_02)

- Text ↔ ULID casting with round-trip validation
- Timestamp ↔ ULID casting with precision checks
- UUID ↔ ULID casting
- Binary ↔ ULID casting with byte-level validation
- Comprehensive round-trip tests for all type combinations
- Precision preservation verification

### Monotonic Generation (test_03)

- Ordering properties and lexicographic sorting
- Consecutive generation uniqueness
- Batch monotonicity validation
- Performance under load (1000+ ULIDs)
- Window function testing with LAG operations
- Text vs binary ordering consistency

### Stress Tests (test_04)

- Small batch generation (100 ULIDs)
- Medium batch generation (1,000 ULIDs)
- Large batch generation (10,000 ULIDs)
- Very large batch generation (100,000 ULIDs)
- Massive batch generation (1,000,000 ULIDs) - configurable
- Performance benchmarks with timing measurements

### Binary Storage (test_05)

- Binary representation validation (16 bytes)
- Storage efficiency verification
- System table verification (`pg_type`, `pg_proc`)
- Round-trip binary operations
- Multiple binary round-trip consistency

### Database Operations (test_06)

- Table creation with ULID columns and default values
- Index creation and usage
- Range queries and filtering
- Sorting and ordering operations
- Aggregation functions
- Join operations with ULID columns
- Foreign key relationships

### Error Handling (test_07)

- Invalid ULID text input handling
- Invalid timestamp input validation
- Invalid UUID input handling
- Invalid bytea input validation
- Function parameter validation
- Type coercion error handling
- Constraint violation testing
- Transactional rollback behavior
- Informative error message validation

## Configuration

### Environment Variables

- `PGHOST` - PostgreSQL host (default: localhost)
- `PGDATABASE` - Database name (default: testdb)
- `PGUSER` - Database user (default: postgres)
- `PGPASSWORD` - Database password (default: empty)
- `PGPORT` - Database port (default: 5432)
- `ULID_STRESS_MAX` - Maximum stress test size (default: 100,000)

### Test Limits

- Stress tests are limited by `ULID_STRESS_MAX` environment variable
- Some tests are skipped if required functions are not available
- Performance tests include timing measurements
- Memory usage is monitored for large batch operations

## Expected Results

All tests should pass with the following characteristics:

- **ULID Generation**: ~1,000+ ULIDs/second
- **Binary Storage**: 16 bytes per ULID
- **Text Representation**: 26 characters per ULID
- **Monotonic Ordering**: Always maintained across generations
- **Uniqueness**: 100% guaranteed within reasonable limits
- **Casting**: All operations work correctly with proper error handling
- **Performance**: Stress tests complete within reasonable time limits

## Troubleshooting

### Common Issues

1. **Database Connection Errors**:
   - Verify PostgreSQL is running
   - Check connection parameters in environment variables
   - Ensure database exists and is accessible

2. **Extension Not Found**:
   - Install the ULID extension: `CREATE EXTENSION ulid;`
   - Check extension is in the correct schema
   - Verify extension files are properly installed

3. **Missing Functions**:
   - Some tests may be skipped if functions are not available
   - Check that all required functions are properly installed
   - Verify function signatures match expected parameters

4. **Performance Issues**:
   - Adjust `ULID_STRESS_MAX` for your system capabilities
   - Monitor system resources during stress tests
   - Consider running tests on a dedicated test system

5. **Test Failures**:
   - Check PostgreSQL logs for detailed error messages
   - Verify all dependencies are installed
   - Run individual test files to isolate issues
   - Check that test database is clean and properly configured

### Debug Mode

Run tests with additional debugging information:

```bash
python -m pytest test/python/ -v -s --tb=short
```

## Contributing

When adding new tests:

1. Follow the existing naming convention (`test_XX_category.py`)
2. Include proper docstrings and comments
3. Use appropriate assertions with descriptive messages
4. Handle edge cases and error conditions
5. Include performance considerations for stress tests
6. Update this README with new test categories
