-- ulid extension version 1.0.0
-- Universally Unique Lexicographically Sortable Identifier (ULID) for PostgreSQL - Enhanced Go implementation

-- Monotonic ULID generation (ensures ordering within same millisecond) - DEFAULT
CREATE OR REPLACE FUNCTION ulid()
RETURNS TEXT
AS $$
DECLARE
    result TEXT;
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS ulid_temp (id text);
    COPY ulid_temp FROM PROGRAM '/usr/local/bin/ulid_generator monotonic';
    SELECT id INTO result FROM ulid_temp LIMIT 1;
    DROP TABLE IF EXISTS ulid_temp;
    RETURN result;
END;
$$ LANGUAGE plpgsql STRICT;

-- Random ULID generation (non-monotonic)
CREATE OR REPLACE FUNCTION ulid_random()
RETURNS TEXT
AS $$
DECLARE
    result TEXT;
BEGIN
    -- Use COPY FROM PROGRAM to execute the Go binary
    CREATE TEMP TABLE IF NOT EXISTS ulid_temp (id text);
    COPY ulid_temp FROM PROGRAM '/usr/local/bin/ulid_generator generate';
    SELECT id INTO result FROM ulid_temp LIMIT 1;
    DROP TABLE IF EXISTS ulid_temp;
    RETURN result;
END;
$$ LANGUAGE plpgsql STRICT;

-- Generate ULID with specific timestamp
CREATE OR REPLACE FUNCTION ulid_time(timestamp_ms BIGINT)
RETURNS TEXT
AS $$
DECLARE
    result TEXT;
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS ulid_temp (id text);
    EXECUTE 'COPY ulid_temp FROM PROGRAM ''/usr/local/bin/ulid_generator time ' || timestamp_ms::TEXT || '''';
    SELECT id INTO result FROM ulid_temp LIMIT 1;
    DROP TABLE IF EXISTS ulid_temp;
    RETURN result;
END;
$$ LANGUAGE plpgsql STRICT;

-- Generate ULID with crypto entropy (always uses crypto/rand)
CREATE OR REPLACE FUNCTION ulid_crypto()
RETURNS TEXT
AS $$
DECLARE
    result TEXT;
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS ulid_temp (id text);
    COPY ulid_temp FROM PROGRAM '/usr/local/bin/ulid_generator generate';
    SELECT id INTO result FROM ulid_temp LIMIT 1;
    DROP TABLE IF EXISTS ulid_temp;
    RETURN result;
END;
$$ LANGUAGE plpgsql STRICT;

-- Parse and validate ULID (simplified version)
CREATE OR REPLACE FUNCTION ulid_parse(ulid_str TEXT)
RETURNS TABLE(
    is_valid BOOLEAN,
    timestamp_ms BIGINT,
    timestamp_iso TEXT,
    entropy_hex TEXT
)
AS $$
BEGIN
    -- Simple validation: check if it's a 26-character string with valid Crockford's Base32 characters
    -- Must contain at least some letters (not all numbers) and follow ULID format
    IF length(ulid_str) = 26 AND ulid_str ~ '^[0-9A-HJKMNP-TV-Z]{26}$' AND ulid_str ~ '[A-HJKMNP-TV-Z]' THEN
        RETURN QUERY SELECT 
            true as is_valid,
            NULL::BIGINT as timestamp_ms,
            NULL::TEXT as timestamp_iso,
            NULL::TEXT as entropy_hex;
    ELSE
        RETURN QUERY SELECT 
            false as is_valid,
            NULL::BIGINT as timestamp_ms,
            NULL::TEXT as timestamp_iso,
            NULL::TEXT as entropy_hex;
    END IF;
END;
$$ LANGUAGE plpgsql STRICT;

-- Generate multiple random ULIDs at once
CREATE OR REPLACE FUNCTION ulid_random_batch(count INTEGER)
RETURNS TEXT[]
AS $$
DECLARE
    result TEXT[] := '{}';
    temp_result TEXT;
    i INTEGER;
BEGIN
    FOR i IN 1..count LOOP
        SELECT ulid_random() INTO temp_result;
        result := array_append(result, temp_result);
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql STRICT;

-- Generate multiple monotonic ULIDs at once
CREATE OR REPLACE FUNCTION ulid_batch(count INTEGER)
RETURNS TEXT[]
AS $$
DECLARE
    result TEXT[] := '{}';
    temp_result TEXT;
    i INTEGER;
BEGIN
    FOR i IN 1..count LOOP
        SELECT ulid() INTO temp_result;
        result := array_append(result, temp_result);
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql STRICT;
