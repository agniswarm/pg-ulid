# PostgreSQL ULID and ObjectId Extension

A PostgreSQL extension that provides ULID (Universally Unique Lexicographically Sortable Identifier) and MongoDB ObjectId support with full type integration, casting operations, and comprehensive functionality.

## Features

- **Custom Types**: Native PostgreSQL types with efficient binary storage
  - `ulid`: 16-byte binary storage
  - `objectid`: 12-byte binary storage
- **Generation Functions**: Random, monotonic, and timestamp-based generation for both types
- **Casting Support**: Seamless conversion between all types and standard PostgreSQL types
- **Cross-Type Conversion**: Bidirectional conversion between ULID and ObjectId
- **Comparison Operators**: Full set of comparison operators for sorting and indexing
- **Timestamp Extraction**: Extract timestamps from both ULID and ObjectId
- **Cross-Platform**: Works on Linux, macOS, and Windows
- **Performance Optimized**: Efficient binary storage and operations

## Installation

### Prerequisites

- PostgreSQL 12+ (tested on PostgreSQL 12-17)
- C compiler (GCC, Clang, or MSVC)
- PostgreSQL development headers
- MongoDB C driver (for ObjectId support)

### Build and Install

```bash
# Clone the repository
git clone <repository-url>
cd ulid-go-extension

# Build the extension
make

# Install the extension
sudo make install

# Connect to PostgreSQL and create the extension
psql -d your_database
CREATE EXTENSION ulid;
```

### Docker

```bash
# Build Docker image
docker build -t postgres-ulid .

# Run PostgreSQL with ULID extension
docker run -d --name postgres-ulid -e POSTGRES_PASSWORD=password -p 5432:5432 postgres-ulid
```

## Usage

### Basic ULID Generation

```sql
-- Generate a monotonic ULID (guaranteed sortable)
SELECT ulid();

-- Generate a random ULID
SELECT ulid_random();

-- Generate ULID with specific timestamp (in milliseconds)
SELECT ulid_generate_with_timestamp(1640995200000); -- 2022-01-01 00:00:00 UTC
```

### Basic ObjectId Generation

```sql
-- Generate an ObjectId
SELECT objectid();

-- Generate a random ObjectId
SELECT objectid_random();

-- Generate ObjectId with specific timestamp (in seconds)
SELECT objectid_generate_with_timestamp(1640995200); -- 2022-01-01 00:00:00 UTC
```

### ULID Type Operations

```sql
-- Create table with ULID primary key
CREATE TABLE users (
    id ulid PRIMARY KEY DEFAULT ulid(),
    name text NOT NULL,
    created_at timestamp DEFAULT now()
);

-- Insert data
INSERT INTO users (name) VALUES ('John Doe'), ('Jane Smith');

-- Query with ULID
SELECT * FROM users WHERE id = '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid;
```

### ObjectId Type Operations

```sql
-- Create table with ObjectId primary key
CREATE TABLE orders (
    id objectid PRIMARY KEY DEFAULT objectid(),
    user_id ulid REFERENCES users(id),
    amount decimal(10,2) NOT NULL,
    created_at timestamp DEFAULT now()
);

-- Insert data
INSERT INTO orders (user_id, amount) 
SELECT id, 99.99 FROM users LIMIT 1;

-- Query with ObjectId
SELECT * FROM orders WHERE id = '507f1f77bcf86cd799439011'::objectid;
```

### Cross-Type Conversion

```sql
-- Convert ULID to ObjectId
SELECT ulid()::objectid;

-- Convert ObjectId to ULID
SELECT objectid()::ulid;

-- Mixed table with both types
CREATE TABLE mixed_table (
    id SERIAL PRIMARY KEY,
    ulid_col ulid,
    objectid_col objectid,
    converted_ulid ulid GENERATED ALWAYS AS (objectid_col::ulid) STORED,
    converted_objectid objectid GENERATED ALWAYS AS (ulid_col::objectid) STORED
);

-- Insert data
INSERT INTO users (name) VALUES ('John Doe'), ('Jane Smith');

-- Query with ULID
SELECT * FROM users WHERE id = '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid;
```

### Casting Operations

```sql
-- Text casting
SELECT '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid::text;

-- Timestamp casting
SELECT '2023-09-15 12:00:00'::timestamp::ulid::timestamp;

-- Timestamptz casting
SELECT '2023-09-15 12:00:00+00'::timestamptz::ulid::timestamptz;

-- UUID casting
SELECT '550e8400-e29b-41d4-a716-446655440000'::uuid::ulid::uuid;

-- Bytea casting
SELECT '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid::bytea;
```

### Timestamp Operations

```sql
-- Extract timestamp from ULID
SELECT ulid_timestamp('01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid);

-- Convert ULID text to timestamp
SELECT ulid_to_timestamp('01ARZ3NDEKTSV4RRFFQ69G5FAV');

-- Generate ULID with specific timestamp
SELECT ulid_time(1640995200000); -- timestamp in milliseconds
```

### Batch Generation

```sql
-- Generate multiple ULIDs
SELECT ulid_batch(5);           -- Array of monotonic ULIDs
SELECT ulid_random_batch(5);    -- Array of random ULIDs
```

### Comparison and Sorting

```sql
-- ULIDs are naturally sortable by generation time
SELECT id, name, created_at 
FROM users 
ORDER BY id;

-- Comparison operations
SELECT * FROM users 
WHERE id > '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid;
```

## API Reference

### Core Functions

| Function | Return Type | Description |
|----------|-------------|-------------|
| `ulid_random()` | `ulid` | Generate a random ULID |
| `ulid()` | `ulid` | Generate a monotonic ULID (guaranteed sortable) |
| `ulid_generate_with_timestamp(bigint)` | `ulid` | Generate ULID with specific timestamp |
| `ulid_timestamp(ulid)` | `bigint` | Extract timestamp from ULID |

### Utility Functions

| Function | Return Type | Description |
|----------|-------------|-------------|
| `ulid_time(bigint)` | `ulid` | Generate ULID with timestamp in milliseconds |
| `ulid_parse(text)` | `ulid` | Parse ULID from text string |
| `ulid_to_timestamp(text)` | `timestamp` | Convert ULID text to timestamp |
| `ulid_timestamp_text(text)` | `bigint` | Extract timestamp from ULID text |

### Batch Functions

| Function | Return Type | Description |
|----------|-------------|-------------|
| `ulid_batch(integer)` | `ulid[]` | Generate array of monotonic ULIDs |
| `ulid_random_batch(integer)` | `ulid[]` | Generate array of random ULIDs |

### UUID Functions

| Function | Return Type | Description |
|----------|-------------|-------------|
| `ulid_to_uuid(ulid)` | `uuid` | Convert ULID to UUID |
| `ulid_from_uuid(uuid)` | `ulid` | Convert UUID to ULID |

### Operators

| Operator | Description |
|----------|-------------|
| `=` | Equal |
| `<>` | Not equal |
| `<` | Less than |
| `<=` | Less than or equal |
| `>` | Greater than |
| `>=` | Greater than or equal |

### Casting

| From Type | To Type | Description |
|-----------|---------|-------------|
| `text` | `ulid` | Parse ULID from string |
| `ulid` | `text` | Convert ULID to string |
| `timestamp` | `ulid` | Convert timestamp to ULID |
| `ulid` | `timestamp` | Extract timestamp from ULID |
| `timestamptz` | `ulid` | Convert timestamptz to ULID |
| `ulid` | `timestamptz` | Extract timestamptz from ULID |
| `uuid` | `ulid` | Convert UUID to ULID |
| `ulid` | `uuid` | Convert ULID to UUID |
| `ulid` | `bytea` | Convert ULID to binary |
| `bytea` | `ulid` | Convert binary to ULID |

## Performance

- **Storage**: 16 bytes per ULID (same as UUID)
- **Indexing**: Full B-tree and hash index support
- **Sorting**: Natural lexicographic ordering by timestamp
- **Generation**: ~1M ULIDs/second on modern hardware

## Testing

Comprehensive Python tests are available using pytest. See [test/python/README.md](test/python/README.md) for detailed testing information.

```bash
# Run all tests (ULID, ObjectId, cross-type, and integration)
python -m pytest test/python/ -v

# Run tests by type
python -m pytest test/python/ulid/ -v          # ULID-specific tests
python -m pytest test/python/objectid/ -v      # ObjectId-specific tests
python -m pytest test/python/cross-type/ -v    # Conversion tests
python -m pytest test/python/integration/ -v   # Mixed operations tests

# Run specific test files
python -m pytest test/python/ulid/test_01_basic_functionality.py -v
python -m pytest test/python/objectid/test_01_basic_functionality.py -v
```

## Development

### Building from Source

```bash
# Install dependencies
# Ubuntu/Debian
sudo apt-get install postgresql-server-dev-15 build-essential

# macOS
brew install postgresql

# Windows
# Install PostgreSQL with development tools

# Build
make clean
make

# Test (see test/python/README.md for detailed testing)
python -m pytest test/python/ -v
```

### Project Structure

```sh
├── src/
│   └── ulid.c              # Main implementation
├── sql/
│   └── ulid--0.1.1.sql     # SQL definitions
├── test/
│   └── python/             # Python test suite
├── Makefile                # Unix build
├── Makefile.win            # Windows build
└── ulid.control            # Extension metadata
```

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## Changelog

See CHANGELOG.md for version history and changes.

## Support

- **Issues**: Report bugs and request features on GitHub
- **Documentation**: See [test/python/README.md](test/python/README.md) for comprehensive testing and usage examples
- **Performance**: ULIDs are designed for high-performance applications

## Related Projects

- [ULID Specification](https://github.com/ulid/spec)
- [PostgreSQL](https://www.postgresql.org/)
- [ULID JavaScript](https://github.com/ulid/javascript)
