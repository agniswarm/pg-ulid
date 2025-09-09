# ULID and ObjectId Extension Python Tests

Comprehensive Python test suite for the PostgreSQL ULID and ObjectId extension using pytest.

## Overview

This test suite provides comprehensive testing for both ULID and MongoDB ObjectId PostgreSQL extensions, covering:
- Basic ULID and ObjectId generation and functionality
- Casting operations between types and other PostgreSQL types
- Monotonic generation and ordering
- Cross-type conversion between ULID and ObjectId
- Stress testing and performance
- Binary storage and efficiency
- Database operations and constraints
- Error handling and edge cases
- Mixed operations and integration testing

## Test Organization

The test suite is organized into specialized folders:

```
test/python/
├── ulid/                    # ULID-specific tests
│   ├── test_01_basic_functionality.py
│   ├── test_02_casting_operations.py
│   ├── test_03_monotonic_generation.py
│   ├── test_04_stress_tests.py
│   ├── test_05_binary_storage.py
│   ├── test_06_database_operations.py
│   └── test_07_error_handling.py
├── objectid/                # ObjectId-specific tests
│   ├── test_01_basic_functionality.py
│   └── test_02_casting_operations.py
├── cross-type/              # Conversion tests
│   └── test_01_ulid_objectid_conversion.py
├── integration/             # Mixed operations tests
│   └── test_01_mixed_operations.py
├── requirements.txt         # Python dependencies
└── README.md               # This file
```

## Setup

### Prerequisites

- Python 3.7+
- PostgreSQL 12+ with the ULID extension installed
- MongoDB C driver (for ObjectId support)
- pytest
- psycopg2

### Installation

```bash
# Install Python dependencies
pip install -r requirements.txt

# Or install manually
pip install pytest psycopg2
```

### Database Configuration

The tests connect to a PostgreSQL database. Configure the connection in each test file:

```python
DB_CONFIG = {
    'host': 'localhost',
    'port': 5435,
    'database': 'testdb',
    'user': 'testuser',
    'password': 'testpass'
}
```

## Running Tests

### Run All Tests

```bash
# From the test/python directory - runs all tests in all folders
python -m pytest -v

# Or run pytest on specific directories
python -m pytest ulid/ objectid/ cross-type/ integration/ -v
```

### Run Tests by Type

```bash
# Run only ULID tests
python -m pytest ulid/ -v

# Run only ObjectId tests
python -m pytest objectid/ -v

# Run only conversion tests
python -m pytest cross-type/ -v

# Run only integration tests
python -m pytest integration/ -v
```

### Run Specific Test Files

```bash
# Run specific test file
python -m pytest ulid/test_01_basic_functionality.py -v

# Run with specific test class
python -m pytest ulid/test_01_basic_functionality.py::TestULIDBasicFunctionality -v

# Run specific test method
python -m pytest ulid/test_01_basic_functionality.py::TestULIDBasicFunctionality::test_ulid_generation -v
```

## Test Structure

### ULID Tests (`ulid/`)

1. **test_01_basic_functionality.py** - Basic ULID generation and core functionality
2. **test_02_casting_operations.py** - Type casting between ULID and other PostgreSQL types
3. **test_03_monotonic_generation.py** - Monotonic ULID generation and ordering
4. **test_04_stress_tests.py** - Stress testing and performance validation
5. **test_05_binary_storage.py** - Binary storage efficiency and operations
6. **test_06_database_operations.py** - Database operations, constraints, and indexing
7. **test_07_error_handling.py** - Error handling and edge cases

### ObjectId Tests (`objectid/`)

1. **test_01_basic_functionality.py** - Basic ObjectId generation and core functionality
2. **test_02_casting_operations.py** - Type casting between ObjectId and other PostgreSQL types

### Cross-Type Tests (`cross-type/`)

1. **test_01_ulid_objectid_conversion.py** - Conversion between ULID and ObjectId types

### Integration Tests (`integration/`)

1. **test_01_mixed_operations.py** - Mixed operations using both ULID and ObjectId types

## Test Features

### Comprehensive Coverage

- **Function Testing**: All ULID and ObjectId functions and operators
- **Type Safety**: Proper type handling and validation
- **Cross-Type Conversion**: Bidirectional conversion between ULID and ObjectId
- **Performance**: Stress testing and timing validation
- **Error Handling**: Invalid input handling and error conditions
- **Database Integration**: Full PostgreSQL integration testing
- **Mixed Operations**: Tests using both types together

### Test Data

- **Random Generation**: Uses random generation for uniqueness testing
- **Specific Timestamps**: Uses fixed timestamps for deterministic testing
- **Edge Cases**: Tests boundary conditions and edge cases
- **Invalid Inputs**: Tests error handling with invalid data
- **Cross-Type Data**: Tests conversion between different ID types

### Assertions

- **Type Validation**: Ensures correct return types
- **Format Validation**: Validates string format and length
- **Uniqueness**: Verifies uniqueness across generations
- **Ordering**: Validates lexicographic ordering properties
- **Performance**: Validates performance characteristics
- **Conversion Accuracy**: Validates cross-type conversions

## Expected Results

### Successful Test Run

```bash
$ python -m pytest -v
========================= test session starts =========================
platform linux -- Python 3.9.7, pytest-6.2.5, py-1.10.0, pluggy-0.13.1
rootdir: /path/to/test/python
collected 255 items

ulid/test_01_basic_functionality.py::TestULIDBasicFunctionality::test_ulid_type_exists PASSED
ulid/test_01_basic_functionality.py::TestULIDBasicFunctionality::test_ulid_generation PASSED
...
objectid/test_01_basic_functionality.py::TestObjectIdBasicFunctionality::test_objectid_type_exists PASSED
objectid/test_01_basic_functionality.py::TestObjectIdBasicFunctionality::test_objectid_generation PASSED
...
cross-type/test_01_ulid_objectid_conversion.py::TestULIDObjectIdConversion::test_ulid_to_objectid_cast PASSED
cross-type/test_01_ulid_objectid_conversion.py::TestULIDObjectIdConversion::test_objectid_to_ulid_cast PASSED
...
integration/test_01_mixed_operations.py::TestMixedOperations::test_mixed_table_creation PASSED
integration/test_01_mixed_operations.py::TestMixedOperations::test_mixed_indexing PASSED
...

========================= 255 passed in 68.45s =========================
```

### Test Categories

- **ULID Tests**: ~150 tests
- **ObjectId Tests**: ~50 tests  
- **Cross-Type Tests**: ~25 tests
- **Integration Tests**: ~30 tests

**Total**: ~255 comprehensive tests

## Troubleshooting

### Common Issues

1. **Database Connection**: Ensure PostgreSQL is running and accessible
2. **Extension Not Installed**: Verify both ULID and ObjectId extensions are installed
3. **MongoDB C Driver**: Ensure MongoDB C driver is installed for ObjectId support
4. **Permission Issues**: Check database user permissions
5. **Python Dependencies**: Ensure all required packages are installed

### Debug Mode

Run tests with debug output:

```bash
python -m pytest -v -s --tb=short
```

### Verbose Output

For detailed test output:

```bash
python -m pytest -v --tb=long
```

## Contributing

### Adding New Tests

1. Create test methods in appropriate test classes
2. Follow naming convention: `test_<description>`
3. Add proper docstrings and assertions
4. Ensure tests are deterministic and isolated
5. Place tests in the appropriate folder based on functionality

### Test Guidelines

- Use descriptive test names
- Include comprehensive docstrings
- Test both success and failure cases
- Validate return types and formats
- Test edge cases and boundary conditions
- Test cross-type conversions when applicable

### Code Style

- Follow PEP 8 guidelines
- Use type hints where appropriate
- Include proper error handling
- Document complex test logic
- Organize tests by functionality in appropriate folders
