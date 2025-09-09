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
AS 'MODULE_PATHNAME', 'ulid_in'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_out(ulid)
RETURNS cstring
AS 'MODULE_PATHNAME', 'ulid_out'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_send(ulid)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ulid_send'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_recv(internal)
RETURNS ulid
AS 'MODULE_PATHNAME', 'ulid_recv'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_cmp(ulid, ulid)
RETURNS integer
AS 'MODULE_PATHNAME', 'ulid_cmp'
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
AS 'MODULE_PATHNAME', 'ulid_lt'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_le(ulid, ulid)
RETURNS boolean
AS 'MODULE_PATHNAME', 'ulid_le'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_eq(ulid, ulid)
RETURNS boolean
AS 'MODULE_PATHNAME', 'ulid_eq'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_ge(ulid, ulid)
RETURNS boolean
AS 'MODULE_PATHNAME', 'ulid_ge'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_gt(ulid, ulid)
RETURNS boolean
AS 'MODULE_PATHNAME', 'ulid_gt'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_ne(ulid, ulid)
RETURNS boolean
AS 'MODULE_PATHNAME', 'ulid_ne'
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
AS 'MODULE_PATHNAME', 'ulid_hash'
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
AS 'MODULE_PATHNAME', 'ulid_generate'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION ulid()
RETURNS ulid
AS 'MODULE_PATHNAME', 'ulid_generate_monotonic'
LANGUAGE C VOLATILE;

-- ============================================================================
-- ULID UTILITY FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION ulid_timestamp(ulid)
RETURNS bigint
AS 'MODULE_PATHNAME', 'ulid_timestamp'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_to_uuid(ulid)
RETURNS uuid
AS 'MODULE_PATHNAME', 'ulid_to_uuid'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION ulid_from_uuid(uuid)
RETURNS ulid
AS 'MODULE_PATHNAME', 'ulid_from_uuid'
LANGUAGE C IMMUTABLE STRICT;

-- ============================================================================
-- ULID CORE FUNCTIONS (C-based)
-- ============================================================================

-- Generate ULID with specific timestamp
CREATE OR REPLACE FUNCTION ulid_generate_with_timestamp(timestamp_ms BIGINT)
RETURNS ulid
AS 'MODULE_PATHNAME', 'ulid_generate_with_timestamp'
LANGUAGE C IMMUTABLE STRICT;

-- ============================================================================
-- OBJECTID TYPE DEFINITION
-- ============================================================================

-- Define the ObjectId type
CREATE TYPE objectid;

-- Define C functions for the ObjectId type
CREATE OR REPLACE FUNCTION objectid_in(cstring)
RETURNS objectid
AS 'MODULE_PATHNAME', 'objectid_in'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_out(objectid)
RETURNS cstring
AS 'MODULE_PATHNAME', 'objectid_out'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_send(objectid)
RETURNS bytea
AS 'MODULE_PATHNAME', 'objectid_send'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_recv(internal)
RETURNS objectid
AS 'MODULE_PATHNAME', 'objectid_recv'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_cmp(objectid, objectid)
RETURNS integer
AS 'MODULE_PATHNAME', 'objectid_cmp'
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
AS 'MODULE_PATHNAME', 'objectid_lt'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_le(objectid, objectid)
RETURNS boolean
AS 'MODULE_PATHNAME', 'objectid_le'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_eq(objectid, objectid)
RETURNS boolean
AS 'MODULE_PATHNAME', 'objectid_eq'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_ge(objectid, objectid)
RETURNS boolean
AS 'MODULE_PATHNAME', 'objectid_ge'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_gt(objectid, objectid)
RETURNS boolean
AS 'MODULE_PATHNAME', 'objectid_gt'
LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION objectid_ne(objectid, objectid)
RETURNS boolean
AS 'MODULE_PATHNAME', 'objectid_ne'
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
AS 'MODULE_PATHNAME', 'objectid_hash'
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
AS 'MODULE_PATHNAME', 'objectid_generate'
LANGUAGE C VOLATILE;

-- ============================================================================
-- OBJECTID UTILITY FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION objectid_time(objectid)
RETURNS bigint
AS 'MODULE_PATHNAME', 'objectid_time'
LANGUAGE C IMMUTABLE STRICT;

-- ============================================================================
-- OBJECTID CORE FUNCTIONS (C-based)
-- ============================================================================

-- Generate ObjectId with specific timestamp
CREATE OR REPLACE FUNCTION objectid_generate_with_timestamp(timestamp_val BIGINT)
RETURNS objectid
AS 'MODULE_PATHNAME', 'objectid_generate_with_timestamp'
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
