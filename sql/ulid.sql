-- ULID Extension for PostgreSQL
-- Version 0.2.0

-- ============================================================================
-- ULID TYPE DEFINITION
-- ============================================================================

-- Define the ULID type
CREATE TYPE ulid;

-- Define C functions for the ULID type
CREATE OR REPLACE FUNCTION ulid_in(cstring)
RETURNS ulid
AS '$libdir/ulid', 'ulid_in'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_out(ulid)
RETURNS cstring
AS '$libdir/ulid', 'ulid_out'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_send(ulid)
RETURNS bytea
AS '$libdir/ulid', 'ulid_send'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_recv(internal)
RETURNS ulid
AS '$libdir/ulid', 'ulid_recv'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_cmp(ulid, ulid)
RETURNS integer
AS '$libdir/ulid', 'ulid_cmp'
LANGUAGE C IMMUTABLE STRICT;

-- Define the ULID type
CREATE TYPE ulid (
    INPUT = ulid_in,
    OUTPUT = ulid_out,
    SEND = ulid_send,
    RECEIVE = ulid_recv,
    INTERNALLENGTH = 16,
    PASSEDBYVALUE = false,
    ALIGNMENT = char,
    STORAGE = plain
);

-- ============================================================================
-- ULID COMPARISON FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION ulid_lt(ulid, ulid)
RETURNS boolean
AS '$libdir/ulid', 'ulid_lt'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_le(ulid, ulid)
RETURNS boolean
AS '$libdir/ulid', 'ulid_le'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_eq(ulid, ulid)
RETURNS boolean
AS '$libdir/ulid', 'ulid_eq'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_ge(ulid, ulid)
RETURNS boolean
AS '$libdir/ulid', 'ulid_ge'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_gt(ulid, ulid)
RETURNS boolean
AS '$libdir/ulid', 'ulid_gt'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_ne(ulid, ulid)
RETURNS boolean
AS '$libdir/ulid', 'ulid_ne'
LANGUAGE C IMMUTABLE STRICT;

-- ============================================================================
-- ULID OPERATORS
-- ============================================================================

CREATE OPERATOR < (LEFTARG = ulid, RIGHTARG = ulid, PROCEDURE = ulid_lt);
CREATE OPERATOR <= (LEFTARG = ulid, RIGHTARG = ulid, PROCEDURE = ulid_le);
CREATE OPERATOR = (LEFTARG = ulid, RIGHTARG = ulid, PROCEDURE = ulid_eq);
CREATE OPERATOR >= (LEFTARG = ulid, RIGHTARG = ulid, PROCEDURE = ulid_ge);
CREATE OPERATOR > (LEFTARG = ulid, RIGHTARG = ulid, PROCEDURE = ulid_gt);
CREATE OPERATOR <> (LEFTARG = ulid, RIGHTARG = ulid, PROCEDURE = ulid_ne);

-- ============================================================================
-- ULID OPERATOR CLASSES
-- ============================================================================

CREATE OPERATOR CLASS ulid_ops
    DEFAULT FOR TYPE ulid USING btree AS
    OPERATOR 1 <,
    OPERATOR 2 <=,
    OPERATOR 3 =,
    OPERATOR 4 >=,
    OPERATOR 5 >,
    FUNCTION 1 ulid_cmp(ulid, ulid);

-- Hash function for ULID type
CREATE OR REPLACE FUNCTION ulid_hash(ulid)
RETURNS integer
AS '$libdir/ulid', 'ulid_hash'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR CLASS ulid_hash_ops
    DEFAULT FOR TYPE ulid USING hash AS
    OPERATOR 1 =,
    FUNCTION 1 ulid_hash(ulid);

-- ============================================================================
-- ULID GENERATION FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION ulid_random()
RETURNS ulid
AS '$libdir/ulid', 'ulid_generate'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION ulid()
RETURNS ulid
AS '$libdir/ulid', 'ulid_generate_monotonic'
LANGUAGE C VOLATILE;

-- ============================================================================
-- ULID UTILITY FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION ulid_timestamp(ulid)
RETURNS bigint
AS '$libdir/ulid', 'ulid_timestamp'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_to_uuid(ulid)
RETURNS uuid
AS '$libdir/ulid', 'ulid_to_uuid'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_from_uuid(uuid)
RETURNS ulid
AS '$libdir/ulid', 'ulid_from_uuid'
LANGUAGE C IMMUTABLE STRICT;

-- ============================================================================
-- ULID CORE FUNCTIONS (C-based)
-- ============================================================================

-- Generate ULID with specific timestamp
CREATE OR REPLACE FUNCTION ulid_generate_with_timestamp(timestamp_ms BIGINT)
RETURNS ulid
AS '$libdir/ulid', 'ulid_generate_with_timestamp'
LANGUAGE C IMMUTABLE STRICT;

-- ============================================================================
-- ULID CONVENIENCE FUNCTIONS (SQL-based)
-- ============================================================================

-- Generate ULID with specific timestamp
CREATE OR REPLACE FUNCTION ulid_time(timestamp_ms BIGINT)
RETURNS ulid
AS $$
    SELECT ulid_generate_with_timestamp(timestamp_ms);
$$ LANGUAGE sql VOLATILE;

-- Parse and validate ULID
CREATE OR REPLACE FUNCTION ulid_parse(ulid_str TEXT)
RETURNS ulid
AS $$
    SELECT ulid_in(ulid_str::cstring);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Extract timestamp from ULID text
CREATE OR REPLACE FUNCTION ulid_timestamp_text(ulid_str TEXT)
RETURNS BIGINT
AS $$
    SELECT ulid_timestamp(ulid_in(ulid_str::cstring));
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Convert ULID text to timestamp
CREATE OR REPLACE FUNCTION ulid_to_timestamp(ulid_str TEXT)
RETURNS TIMESTAMP
AS $$
    SELECT to_timestamp(ulid_timestamp(ulid_in(ulid_str::cstring)) / 1000.0);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Batch generation functions
CREATE OR REPLACE FUNCTION ulid_batch(count INTEGER)
RETURNS ulid[]
AS $$
    SELECT array_agg(ulid()) FROM generate_series(1, count);
$$ LANGUAGE sql VOLATILE;

CREATE OR REPLACE FUNCTION ulid_random_batch(count INTEGER)
RETURNS ulid[]
AS $$
    SELECT array_agg(ulid_random()) FROM generate_series(1, count);
$$ LANGUAGE sql VOLATILE;

-- ============================================================================
-- ULID CASTING FUNCTIONS
-- ============================================================================

-- Convert timestamp to ULID (for casting)
CREATE OR REPLACE FUNCTION timestamp_to_ulid_cast(timestamp_val TIMESTAMP)
RETURNS ulid
AS $$
    SELECT ulid_generate_with_timestamp(EXTRACT(EPOCH FROM timestamp_val)::BIGINT * 1000);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Convert timestamptz to ULID (for casting)
CREATE OR REPLACE FUNCTION timestamptz_to_ulid_cast(timestamp_val TIMESTAMPTZ)
RETURNS ulid
AS $$
    SELECT ulid_generate_with_timestamp(EXTRACT(EPOCH FROM timestamp_val)::BIGINT * 1000);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Convert ULID type to timestamp (for casting)
CREATE OR REPLACE FUNCTION ulid_to_timestamp_cast(ulid_val ulid)
RETURNS TIMESTAMP
AS $$
    SELECT to_timestamp(ulid_timestamp(ulid_val) / 1000.0);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Convert ULID to timestamptz (for casting)
CREATE OR REPLACE FUNCTION ulid_to_timestamptz_cast(ulid_val ulid)
RETURNS TIMESTAMPTZ
AS $$
    SELECT to_timestamp(ulid_timestamp(ulid_val) / 1000.0);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Define casting functions with proper type signatures
CREATE OR REPLACE FUNCTION text_to_ulid_cast(text_val text)
RETURNS ulid
AS $$
    SELECT ulid_in(text_val::cstring);
$$ LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_to_text_cast(ulid_val ulid)
RETURNS text
AS $$
    SELECT ulid_out(ulid_val)::text;
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Convert ULID to bytea (for casting)
CREATE OR REPLACE FUNCTION ulid_to_bytea_cast(ulid_val ulid)
RETURNS bytea
AS $$
    SELECT ulid_send(ulid_val);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Convert bytea to ULID (for casting) - using proper binary conversion
CREATE OR REPLACE FUNCTION bytea_to_ulid_cast(bytea_val bytea)
RETURNS ulid
AS $$
    SELECT ulid_in(encode(bytea_val, 'base64')::cstring);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- ============================================================================
-- ULID CASTS
-- ============================================================================

CREATE CAST (text AS ulid) WITH FUNCTION text_to_ulid_cast(text) AS ASSIGNMENT;
CREATE CAST (ulid AS text) WITH FUNCTION ulid_to_text_cast(ulid) AS ASSIGNMENT;
CREATE CAST (timestamp AS ulid) WITH FUNCTION timestamp_to_ulid_cast(timestamp) AS ASSIGNMENT;
CREATE CAST (ulid AS timestamp) WITH FUNCTION ulid_to_timestamp_cast(ulid) AS ASSIGNMENT;
CREATE CAST (timestamptz AS ulid) WITH FUNCTION timestamptz_to_ulid_cast(timestamptz) AS ASSIGNMENT;
CREATE CAST (ulid AS timestamptz) WITH FUNCTION ulid_to_timestamptz_cast(ulid) AS ASSIGNMENT;
CREATE CAST (ulid AS bytea) WITH FUNCTION ulid_to_bytea_cast(ulid) AS ASSIGNMENT;
CREATE CAST (bytea AS ulid) WITH FUNCTION bytea_to_ulid_cast(bytea) AS ASSIGNMENT;
CREATE CAST (ulid AS uuid) WITH FUNCTION ulid_to_uuid(ulid) AS ASSIGNMENT;
CREATE CAST (uuid AS ulid) WITH FUNCTION ulid_from_uuid(uuid) AS ASSIGNMENT;
