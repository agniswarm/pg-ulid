# ULID Extension Python Tests

This directory contains comprehensive Python tests for the PostgreSQL ULID extension. These tests provide better validation than the SQL tests and can catch more edge cases.

## Test Files

- `test_01_basic_functionality.py` - Tests basic ULID generation and validation
- `test_02_casting_operations.py` - Tests all ULID casting operations between different types
- `test_03_monotonic_generation.py` - Tests ULID monotonic generation and ordering properties
- `test_04_stress_tests.py` - Tests ULID generation under various stress conditions
- `test_05_binary_storage.py` - Tests ULID binary storage and efficiency

## Setup

1. Install Python dependencies:

   ```bash
   pip install -r requirements.txt
   ```

2. Make sure PostgreSQL is running with the ULID extension installed:

   ```bash
   # Start PostgreSQL
   sudo systemctl start postgresql
   
   # Create test database
   createdb testdb
   
   # Install extension
   psql -d testdb -c "CREATE EXTENSION ulid;"
   ```

## Running Tests

### Run All Tests

```bash
python run_all_tests.py
```

### Run Individual Tests

```bash
python test_01_basic_functionality.py
python test_02_casting_operations.py
# ... etc
```

## Test Features

- **Comprehensive Coverage**: Tests all documented functionality
- **Real Assertions**: Uses Python assertions instead of SQL-based testing
- **Performance Testing**: Includes timing and stress tests
- **Error Handling**: Proper exception handling and reporting
- **Cleanup**: Automatic cleanup of test data
- **Detailed Output**: Clear pass/fail reporting with timing information

## Test Categories

### Basic Functionality (test_01)

- ULID generation functions
- Uniqueness validation
- Length validation
- Batch operations
- NULL handling

### Casting Operations (test_02)

- Text ↔ ULID casting
- Timestamp ↔ ULID casting
- UUID ↔ ULID casting
- Binary ↔ ULID casting
- Round-trip validation

### Monotonic Generation (test_03)

- Ordering properties
- Consecutive generation
- Batch monotonicity
- Performance under load

### Stress Tests (test_04)

- Small batch generation (100 ULIDs)
- Medium batch generation (1,000 ULIDs)
- Large batch generation (10,000 ULIDs)
- Very large batch generation (100,000 ULIDs)
- Massive batch generation (1,000,000 ULIDs)
- Performance benchmarks

### Binary Storage (test_05)

- Binary representation validation
- Storage efficiency verification
- System table verification
- Round-trip binary operations

### Database Operations (test_06)

- Table creation with ULID columns
- Index creation and usage
- Range queries
- Sorting and ordering
- Aggregation functions
- Join operations
- Foreign key relationships

### README Functionality (test_07)

- All documented functions
- All documented casting operations
- All documented features
- Comprehensive validation

## Expected Results

All tests should pass with the following characteristics:

- ULID generation: ~1,000 ULIDs/second
- Binary storage: 16 bytes per ULID
- Text representation: 26 characters per ULID
- Monotonic ordering: Always maintained
- Uniqueness: 100% guaranteed
- Casting: All operations work correctly

## Troubleshooting

If tests fail, check:

1. PostgreSQL is running
2. ULID extension is installed
3. Database connection settings
4. Python dependencies are installed
5. Test database exists and is accessible
