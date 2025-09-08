# pg-ulid

Open-source ULID generation for Postgres

Generate Universally Unique Lexicographically Sortable Identifiers (ULIDs) directly in PostgreSQL using **the** [oklog/ulid/v2](https://github.com/oklog/ulid) library. Supports:

- monotonic ULIDs for guaranteed ordering within same millisecond
- time-based ULID generation with custom timestamps
- batch generation for high-throughput scenarios
- ULID parsing and validation
- any [language](#languages) with a Postgres client

Plus [ACID](https://en.wikipedia.org/wiki/ACID) compliance, point-in-time recovery, JOINs, and all of the other [great features](https://www.postgresql.org/about/) of Postgres

[![Build Status](https://github.com/agniswarm/pg-ulid/actions/workflows/ci.yml/badge.svg)](https://github.com/agniswarm/pg-ulid/actions)

## Installation

### Manual Installation

#### Linux and Mac

Compile and install the extension (supports Postgres 13+)

```sh
cd /tmp
git clone --branch v1.0.0 https://github.com/agniswarm/pg-ulid.git
cd pg-ulid
make
make install # may need sudo
```

See the [installation notes](#installation-notes---linux-and-mac) if you run into issues

#### Windows

Ensure [C++ support in Visual Studio](https://learn.microsoft.com/en-us/cpp/build/building-on-the-command-line?view=msvc-170#download-and-install-the-tools) is installed and run `x64 Native Tools Command Prompt for VS [version]` as administrator. Then use `nmake` to build:

```cmd
set "PGROOT=C:\Program Files\PostgreSQL\17"
cd %TEMP%
git clone --branch v1.0.0 https://github.com/agniswarm/pg-ulid.git
cd pg-ulid
nmake /F Makefile.win
nmake /F Makefile.win install
```

See the [installation notes](#installation-notes---windows) if you run into issues

### Docker

Build the Docker image manually:

```sh
git clone --branch v1.0.0 https://github.com/agniswarm/pg-ulid.git
cd pg-ulid
docker build -t pg-ulid .
```

Run with PostgreSQL:

```sh
docker run --name postgres-ulid -e POSTGRES_PASSWORD=password -d pg-ulid
```

## Getting Started

Enable the extension (do this once in each database where you want to use it)

```sql
CREATE EXTENSION ulid;
```

Generate a monotonic ULID (ensures ordering within same millisecond)

```sql
SELECT ulid();
-- 01K4FQ7QN4ZSW0SG5XACGM2HB4
```

Generate multiple ULIDs

```sql
SELECT ulid(), ulid(), ulid();
-- 01K4FQ7QN4ZSW0SG5XACGM2HB4 | 01K4FQ7QN4ZSW0SG5XACGM2HB5 | 01K4FQ7QN4ZSW0SG5XACGM2HB6
```

### Random ULIDs

Generate random ULIDs (non-monotonic):

```sql
SELECT ulid_random();
-- 01K4FQ7QN4ZSW0SG5XACGM2HB4

SELECT ulid_crypto();
-- 01K4FQ7QN4ZSW0SG5XACGM2HB5
```

### Time-based Generation

Generate ULIDs with specific timestamps:

```sql
-- Generate ULID for a specific timestamp (milliseconds since epoch)
SELECT ulid_time(1640995200000);
-- 01FR9EZ7002NVJQ60SA8KWGD5J

-- Generate ULID for current time
SELECT ulid_time(extract(epoch from now()) * 1000);
-- 01K4FQ7QN4ZSW0SG5XACGM2HB4
```

### Batch Operations

Generate multiple ULIDs at once:

```sql
-- Generate 5 monotonic ULIDs
SELECT ulid_batch(5);
-- {01K4FQ7QN4ZSW0SG5XACGM2HB4,01K4FQ7QN4ZSW0SG5XACGM2HB5,01K4FQ7QN4ZSW0SG5XACGM2HB6,01K4FQ7QN4ZSW0SG5XACGM2HB7,01K4FQ7QN4ZSW0SG5XACGM2HB8}

-- Generate 3 random ULIDs
SELECT ulid_random_batch(3);
-- {01K4FQ7QN4ZSW0SG5XACGM2HB4,01K4FQ7QN4ZSW0SG5XACGM2HB5,01K4FQ7QN4ZSW0SG5XACGM2HB6}

-- For high-throughput scenarios, use reasonable batch sizes
SELECT ulid_batch(100) FROM generate_series(1, 10);  -- Generates 1000 ULIDs efficiently
```

## Storing

Create a new table with ULID primary key

```sql
CREATE TABLE events (id TEXT PRIMARY KEY DEFAULT ulid(), data JSONB);
```

Or add a ULID column to an existing table

```sql
ALTER TABLE items ADD COLUMN id TEXT DEFAULT ulid();
```

Insert records with auto-generated ULIDs

```sql
INSERT INTO events (data) VALUES ('{"event": "user_login"}'), ('{"event": "user_logout"}');
```

Or specify ULIDs manually

```sql
INSERT INTO events (id, data) VALUES (ulid(), '{"event": "custom"}');
```

## Querying

Get all events ordered by creation time (ULIDs are lexicographically sortable)

```sql
SELECT * FROM events ORDER BY id;
```

Get events created after a specific ULID

```sql
SELECT * FROM events WHERE id > '01K4FQ7QN4ZSW0SG5XACGM2HB4';
```

Get events created within a time range

```sql
SELECT * FROM events 
WHERE id >= ulid_time(1640995200000)  -- 2022-01-01 00:00:00 UTC
  AND id < ulid_time(1641081600000);  -- 2022-01-02 00:00:00 UTC
```

## Time-based Generation

Generate ULIDs with specific timestamps

```sql
-- Generate ULID for 2022-01-01 00:00:00 UTC
SELECT ulid_time(1640995200000);
-- 01ARZ3NDEKTSV4RRFFQ69G5FAV

-- Generate ULID for current time
SELECT ulid_time(extract(epoch from now()) * 1000);
```

Use for time-based partitioning

```sql
CREATE TABLE logs_2024 (
    id TEXT PRIMARY KEY DEFAULT ulid_time(extract(epoch from now()) * 1000),
    message TEXT
);
```

## Batch Generation

Generate multiple ULIDs efficiently

```sql
-- Generate 5 monotonic ULIDs
SELECT ulid_batch(5);
-- {01K4FQ7QN4ZSW0SG5XACGM2HB4,01K4FQ7QN4ZSW0SG5XACGM2HB5,...}

-- Generate 3 random ULIDs
SELECT ulid_random_batch(3);
-- {01K4FQ7QN4ZSW0SG5XACGM2HB7,01K4FQ7QN4ZSW0SG5XACGM2HB8,...}
```

Use for bulk inserts

```sql
INSERT INTO events (id, data) 
SELECT id, jsonb_build_object('event', 'batch_' || row_number() OVER ())
FROM unnest(ulid_batch(50)) AS id;  -- Use reasonable batch size
```

## Parsing and Validation

Parse ULIDs to extract timestamp and entropy

```sql
SELECT * FROM ulid_parse('01K4FQ7QN4ZSW0SG5XACGM2HB4');
-- ulid_str | timestamp | entropy | time_str
-- 01K4FQ7QN4ZSW0SG5XACGM2HB4 | 1640995200000 | 0x1234567890abcdef | 2022-01-01T00:00:00Z
```

Validate ULID format

```sql
SELECT ulid_parse('invalid-ulid');
-- ERROR: invalid ULID format
```

## Performance

### Loading

Use `COPY` for bulk loading data with ULIDs.

```sql
-- Create table
CREATE TABLE events (id TEXT PRIMARY KEY, data TEXT);

-- Load data using COPY from file (recommended approach)
-- First create a CSV file:
-- 01K4FQ7QN4ZSW0SG5XACGM2HB4,test_event
-- 01K4FQ7QN4ZSW0SG5XACGM2HB5,login_event
-- 01K4FQ7QN4ZSW0SG5XACGM2HB6,logout_event

COPY events (id, data) FROM '/path/to/events.csv' WITH (FORMAT CSV);

-- For JSON data, use INSERT instead
INSERT INTO events (id, data) VALUES 
  ('01K4FQ7QN4ZSW0SG5XACGM2HB4', '{"event":"test"}'),
  ('01K4FQ7QN4ZSW0SG5XACGM2HB5', '{"event":"login"}');
```

###  Querying

Use `EXPLAIN ANALYZE` to debug performance.

```sql
EXPLAIN ANALYZE SELECT * FROM events WHERE id > '01K4FQ7QN4ZSW0SG5XACGM2HB4' ORDER BY id LIMIT 10;
```

For high-throughput scenarios, consider using batch generation:

```sql
-- More efficient than multiple individual calls (use reasonable batch sizes)
SELECT ulid_batch(100) FROM generate_series(1, 10);

-- Generate 500 ULIDs efficiently
SELECT count(*) as total_ulids 
FROM (SELECT unnest(ulid_batch(100)) FROM generate_series(1, 5)) t;
```

## Scaling

Scale ulid the same way you scale Postgres.

Scale vertically by increasing memory, CPU, and storage on a single instance. Use existing tools to [tune parameters](#tuning) and [monitor performance](#monitoring).

Scale horizontally with [replicas](https://www.postgresql.org/docs/current/hot-standby.html), or use [Citus](https://github.com/citusdata/citus) or another approach for sharding.

## Troubleshooting

#### Why isn't a query using an index on ULID columns?

ULID columns can use standard B-tree indexes for ordering and range queries. Make sure you have an index:

```sql
CREATE INDEX ON events (id);
```

#### Why are ULIDs not perfectly ordered?

ULIDs are designed to be lexicographically sortable, but they're not perfectly ordered across different time periods. Within the same millisecond, monotonic ULIDs ensure ordering.

#### Why is batch generation faster?

Batch generation reduces the overhead of multiple function calls and can generate ULIDs more efficiently in bulk.

## Reference

### ULID Functions

Function | Description | Parameters | Returns
--- | --- | --- | ---
`ulid()` | Generate monotonic ULID | None | TEXT
`ulid_random()` | Generate random ULID | None | TEXT
`ulid_time(timestamp_ms)` | Generate ULID with timestamp | BIGINT | TEXT
`ulid_parse(ulid_str)` | Parse and validate ULID | TEXT | TABLE
`ulid_batch(count)` | Generate multiple monotonic ULIDs | INTEGER | TEXT[]
`ulid_random_batch(count)` | Generate multiple random ULIDs | INTEGER | TEXT[]

### ULID Properties

- **Length**: 26 characters
- **Format**: 10 characters timestamp + 16 characters entropy
- **Character set**: Crockford's Base32 (0-9, A-Z excluding I, L, O, U)
- **Sortable**: Lexicographically sortable by creation time
- **Monotonic**: Within same millisecond, ensures ordering
- **URL-safe**: No special characters

## Thanks

Thanks to:

- [oklog/ulid](https://github.com/oklog/ulid) - The original ULID specification and Go implementation
- [ULID Specification](https://github.com/ulid/spec) - The official ULID specification
- [Crockford's Base32](https://www.crockford.com/base32.html) - The encoding used by ULIDs

## History

View the [changelog](https://github.com/agniswarm/pg-ulid/blob/master/CHANGELOG.md)

## Contributing

Everyone is encouraged to help improve this project. Here are a few ways you can help:

- [Report bugs](https://github.com/agniswarm/pg-ulid/issues)
- Fix bugs and [submit pull requests](https://github.com/agniswarm/pg-ulid/pulls)
- Write, clarify, or fix documentation
- Suggest or add new features

To get started with development:

```sh
git clone https://github.com/agniswarm/pg-ulid.git
cd pg-ulid
make
make install
```

For testing, see the [test documentation](test/README.md).
