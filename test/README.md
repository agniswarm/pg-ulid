# ULID Extension Testing

Simple tests for the PostgreSQL ULID extension.

## Prerequisites

- **Docker**: For running PostgreSQL with the extension
- **Go**: Version 1.21 or later

## Quick Start

### 1. Build and Start Docker

```bash
# Build the Docker image
docker build -t pg-ulid-extension .

# Start PostgreSQL with the extension
docker run -d --name pg-ulid-test -e POSTGRES_PASSWORD=test -p 5432:5432 pg-ulid-extension
```

### 2. Run Tests

```bash
cd test

# Run all tests
go test -v

# Run only Go module tests
go test -v -run TestGoModules

# Run only SQL function tests  
go test -v -run TestSQL
```

### 3. Clean Up

```bash
# Stop and remove the container
docker rm -f pg-ulid-test
```

## Test Files

- **`module_test.go`**: Go module dependency tests
- **`ulid_test.go`**: SQL function integration tests  
- **`go.mod`**: Go module dependencies

## Test Categories

### 1. Go Module Tests (`module_test.go`)

- **Basic ULID Generation**: Tests `ulid.Make()` and validation
- **Time-based Generation**: Tests with current, min, max, epoch, and future timestamps
- **Entropy Sources**: Tests default, crypto/rand, zero, and deterministic entropy
- **Parsing Edge Cases**: Tests valid/invalid strings, length validation, character validation
- **ULID Ordering**: Tests time-based and monotonic ordering
- **Monotonic Generation**: Tests monotonic ULID generation with different increments
- **Time Extraction**: Tests timestamp extraction and precision
- **Encoding/Decoding**: Tests Crockford's Base32 encoding validation
- **Extreme Values**: Tests with maximum timestamps and large increments
- **Concurrent Generation**: Tests 1000 concurrent ULID generations for uniqueness
- **Error Handling**: Tests invalid inputs and error conditions
- **String Representation**: Tests consistency and printability

### 2. SQL Function Tests (`ulid_test.go`)

- Tests all ULID functions in PostgreSQL
- Validates database integration
- Ensures proper error handling

## Available Tests

### Module Tests (No Database Required)

- `TestBasicULIDGeneration` - Basic ULID generation and validation
- `TestTimeBasedULIDGeneration` - Time-based ULID generation with edge cases
- `TestEntropySources` - Different entropy sources (default, crypto, zero, deterministic)
- `TestULIDParsingEdgeCases` - Comprehensive parsing with invalid inputs
- `TestULIDOrdering` - Time-based and monotonic ordering
- `TestMonotonicULIDGeneration` - Monotonic ULID generation
- `TestULIDTimeExtraction` - Timestamp extraction and precision
- `TestULIDEncoding` - Crockford's Base32 encoding validation
- `TestExtremeValues` - Maximum timestamps and large increments
- `TestConcurrentGeneration` - 1000 concurrent ULID generations
- `TestErrorHandling` - Invalid inputs and error conditions
- `TestULIDStringRepresentation` - String consistency and printability

### SQL Function Tests (Requires Docker)

- `TestSQLFunctions` - Basic ULID generation in PostgreSQL
- `TestRandomULID` - Random ULID generation
- `TestCryptoULID` - Crypto-secure ULID generation
- `TestTimeBasedULID` - Time-based ULID generation
- `TestBatchULID` - Batch ULID generation
- `TestRandomBatchULID` - Random batch ULID generation
- `TestULIDParsing` - ULID parsing and validation in PostgreSQL

## Troubleshooting

### Database Connection Failed

```bash
Warning: Could not connect to database
Skipping database tests
```

**Solution**: Make sure Docker container is running:

```bash
docker ps
docker logs pg-ulid-test
```

### Port Already in Use

```bash
Error: port 5432 is already allocated
```

**Solution**: Use a different port:

```bash
docker run -d --name pg-ulid-test -e POSTGRES_PASSWORD=test -p 5433:5432 pg-ulid-extension
```

Then update the test configuration in `ulid_test.go`:

```go
const (
    DB_PORT = "5433"  // Change from "5432" to "5433"
)
```

### Go Module Issues

```bash
go: cannot find module providing package
```

**Solution**: Download dependencies:

```bash
cd test
go mod download
go mod tidy
```

## Manual Testing

You can also test the extension manually:

```bash
# Connect to the database
docker exec -it pg-ulid-test psql -U postgres

# Test ULID functions
SELECT ulid();
SELECT ulid_random();
SELECT ulid_crypto();
SELECT ulid_time(1640995200000);
SELECT ulid_batch(5);
SELECT ulid_random_batch(3);
SELECT * FROM ulid_parse('01K4FRQ1CZDHKG25YHF6Q5W0Z1');
```
