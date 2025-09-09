-- Define the ObjectId type
CREATE TYPE objectid;

-- Define C functions for the ObjectId type
CREATE OR REPLACE FUNCTION objectid_in(cstring)
RETURNS objectid
AS '$libdir/ulid', 'objectid_in'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_out(objectid)
RETURNS cstring
AS '$libdir/ulid', 'objectid_out'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_send(objectid)
RETURNS bytea
AS '$libdir/ulid', 'objectid_send'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_recv(internal)
RETURNS objectid
AS '$libdir/ulid', 'objectid_recv'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_cmp(objectid, objectid)
RETURNS integer
AS '$libdir/ulid', 'objectid_cmp'
LANGUAGE C IMMUTABLE STRICT;

-- Define the ObjectId type
CREATE TYPE objectid (
    INPUT = objectid_in,
    OUTPUT = objectid_out,
    SEND = objectid_send,
    RECEIVE = objectid_recv,
    INTERNALLENGTH = 12,
    PASSEDBYVALUE = false,
    ALIGNMENT = char,
    STORAGE = plain
);

-- ============================================================================
-- OBJECTID COMPARISON FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION objectid_lt(objectid, objectid)
RETURNS boolean
AS '$libdir/ulid', 'objectid_lt'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_le(objectid, objectid)
RETURNS boolean
AS '$libdir/ulid', 'objectid_le'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_eq(objectid, objectid)
RETURNS boolean
AS '$libdir/ulid', 'objectid_eq'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_ge(objectid, objectid)
RETURNS boolean
AS '$libdir/ulid', 'objectid_ge'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_gt(objectid, objectid)
RETURNS boolean
AS '$libdir/ulid', 'objectid_gt'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_ne(objectid, objectid)
RETURNS boolean
AS '$libdir/ulid', 'objectid_ne'
LANGUAGE C IMMUTABLE STRICT;

-- ============================================================================
-- OBJECTID OPERATORS
-- ============================================================================

CREATE OPERATOR < (LEFTARG = objectid, RIGHTARG = objectid, PROCEDURE = objectid_lt);
CREATE OPERATOR <= (LEFTARG = objectid, RIGHTARG = objectid, PROCEDURE = objectid_le);
CREATE OPERATOR = (LEFTARG = objectid, RIGHTARG = objectid, PROCEDURE = objectid_eq);
CREATE OPERATOR >= (LEFTARG = objectid, RIGHTARG = objectid, PROCEDURE = objectid_ge);
CREATE OPERATOR > (LEFTARG = objectid, RIGHTARG = objectid, PROCEDURE = objectid_gt);
CREATE OPERATOR <> (LEFTARG = objectid, RIGHTARG = objectid, PROCEDURE = objectid_ne);

-- ============================================================================
-- OBJECTID OPERATOR CLASSES
-- ============================================================================

CREATE OPERATOR CLASS objectid_ops
    DEFAULT FOR TYPE objectid USING btree AS
    OPERATOR 1 <,
    OPERATOR 2 <=,
    OPERATOR 3 =,
    OPERATOR 4 >=,
    OPERATOR 5 >,
    FUNCTION 1 objectid_cmp(objectid, objectid);

-- Hash function for ObjectId type
CREATE OR REPLACE FUNCTION objectid_hash(objectid)
RETURNS integer
AS '$libdir/ulid', 'objectid_hash'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR CLASS objectid_hash_ops
    DEFAULT FOR TYPE objectid USING hash AS
    OPERATOR 1 =,
    FUNCTION 1 objectid_hash(objectid);

-- ============================================================================
-- OBJECTID GENERATION FUNCTIONS
-- ============================================================================

-- Main ObjectId generation function
CREATE OR REPLACE FUNCTION objectid()
RETURNS objectid
AS '$libdir/ulid', 'objectid_generate'
LANGUAGE C VOLATILE;

-- ============================================================================
-- OBJECTID UTILITY FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION objectid_time(objectid)
RETURNS bigint
AS '$libdir/ulid', 'objectid_time'
LANGUAGE C IMMUTABLE STRICT;

-- ============================================================================
-- OBJECTID CORE FUNCTIONS (C-based)
-- ============================================================================

-- Generate ObjectId with specific timestamp
CREATE OR REPLACE FUNCTION objectid_generate_with_timestamp(timestamp_val BIGINT)
RETURNS objectid
AS '$libdir/ulid', 'objectid_generate_with_timestamp'
LANGUAGE C IMMUTABLE STRICT;

-- ============================================================================
-- OBJECTID CONVENIENCE FUNCTIONS (SQL-based)
-- ============================================================================

-- Parse and validate ObjectId
CREATE OR REPLACE FUNCTION objectid_parse(objectid_str TEXT)
RETURNS objectid
AS $$
    SELECT objectid_in(objectid_str::cstring);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Extract timestamp from ObjectId text
CREATE OR REPLACE FUNCTION objectid_timestamp_text(objectid_str TEXT)
RETURNS BIGINT
AS $$
    SELECT objectid_time(objectid_in(objectid_str::cstring));
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Convert ObjectId text to timestamp
CREATE OR REPLACE FUNCTION objectid_to_timestamp(objectid_str TEXT)
RETURNS TIMESTAMP
AS $$
    SELECT to_timestamp(objectid_time(objectid_in(objectid_str::cstring)));
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Batch generation functions
CREATE OR REPLACE FUNCTION objectid_batch(count INTEGER)
RETURNS objectid[]
AS $$
    SELECT array_agg(objectid()) FROM generate_series(1, count);
$$ LANGUAGE sql VOLATILE;

-- ============================================================================
-- OBJECTID CASTING FUNCTIONS
-- ============================================================================

-- Convert timestamp to ObjectId (for casting)
CREATE OR REPLACE FUNCTION timestamp_to_objectid_cast(timestamp_val TIMESTAMP)
RETURNS objectid
AS $$
    SELECT objectid_generate_with_timestamp(EXTRACT(EPOCH FROM timestamp_val)::BIGINT);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Convert timestamptz to ObjectId (for casting)
CREATE OR REPLACE FUNCTION timestamptz_to_objectid_cast(timestamp_val TIMESTAMPTZ)
RETURNS objectid
AS $$
    SELECT objectid_generate_with_timestamp(EXTRACT(EPOCH FROM timestamp_val)::BIGINT);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Convert ObjectId type to timestamp (for casting)
CREATE OR REPLACE FUNCTION objectid_to_timestamp_cast(objectid_val objectid)
RETURNS TIMESTAMP
AS $$
    SELECT to_timestamp(objectid_time(objectid_val));
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Convert ObjectId to timestamptz (for casting)
CREATE OR REPLACE FUNCTION objectid_to_timestamptz_cast(objectid_val objectid)
RETURNS TIMESTAMPTZ
AS $$
    SELECT to_timestamp(objectid_time(objectid_val));
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Define casting functions with proper type signatures
CREATE OR REPLACE FUNCTION text_to_objectid_cast(text_val text)
RETURNS objectid
AS $$
    SELECT objectid_in(text_val::cstring);
$$ LANGUAGE sql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_to_text_cast(objectid_val objectid)
RETURNS text
AS $$
    SELECT objectid_out(objectid_val)::text;
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Convert ObjectId to bytea (for casting)
CREATE OR REPLACE FUNCTION objectid_to_bytea_cast(objectid_val objectid)
RETURNS bytea
AS $$
    SELECT objectid_send(objectid_val);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- Convert bytea to ObjectId (for casting) - using proper binary conversion
CREATE OR REPLACE FUNCTION bytea_to_objectid_cast(bytea_val bytea)
RETURNS objectid
AS $$
    SELECT objectid_in(encode(bytea_val, 'base64')::cstring);
$$ LANGUAGE sql IMMUTABLE STRICT;

-- ============================================================================
-- OBJECTID CASTS
-- ============================================================================

CREATE CAST (text AS objectid) WITH FUNCTION text_to_objectid_cast(text) AS ASSIGNMENT;
CREATE CAST (objectid AS text) WITH FUNCTION objectid_to_text_cast(objectid) AS ASSIGNMENT;
CREATE CAST (timestamp AS objectid) WITH FUNCTION timestamp_to_objectid_cast(timestamp) AS ASSIGNMENT;
CREATE CAST (objectid AS timestamp) WITH FUNCTION objectid_to_timestamp_cast(objectid) AS ASSIGNMENT;
CREATE CAST (timestamptz AS objectid) WITH FUNCTION timestamptz_to_objectid_cast(timestamptz) AS ASSIGNMENT;
CREATE CAST (objectid AS timestamptz) WITH FUNCTION objectid_to_timestamptz_cast(objectid) AS ASSIGNMENT;
CREATE CAST (objectid AS bytea) WITH FUNCTION objectid_to_bytea_cast(objectid) AS ASSIGNMENT;
CREATE CAST (bytea AS objectid) WITH FUNCTION bytea_to_objectid_cast(bytea) AS ASSIGNMENT;
