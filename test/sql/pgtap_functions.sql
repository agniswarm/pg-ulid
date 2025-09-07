-- Clean pgTAP-like Testing Framework
-- Simplified version without function overloading issues

-- Create test result tracking table
DROP TABLE IF EXISTS test_results CASCADE;
CREATE TABLE test_results (
    id SERIAL PRIMARY KEY,
    test_name TEXT,
    test_result TEXT,
    test_message TEXT,
    test_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Test plan function
CREATE OR REPLACE FUNCTION plan(n INTEGER)
RETURNS TEXT AS $$
BEGIN
    DELETE FROM test_results;
    INSERT INTO test_results (test_name, test_result, test_message)
    VALUES ('PLAN', '1..' || n, '');
    RETURN '1..' || n;
END;
$$ LANGUAGE plpgsql;

-- Basic ok function
CREATE OR REPLACE FUNCTION ok(condition BOOLEAN, test_name TEXT, test_message TEXT DEFAULT '')
RETURNS TEXT AS $$
BEGIN
    INSERT INTO test_results (test_name, test_result, test_message)
    VALUES (test_name, CASE WHEN condition THEN 'ok' ELSE 'not ok' END, test_message);
    IF NOT condition THEN
        RAISE EXCEPTION 'Test Failed: % - %', test_name, test_message;
    END IF;
    RETURN CASE WHEN condition THEN 'ok' ELSE 'not ok' END || ' ' || test_name || ' - ' || test_message;
END;
$$ LANGUAGE plpgsql;

-- Equality test
CREATE OR REPLACE FUNCTION is(got ANYELEMENT, expected ANYELEMENT, test_name TEXT, test_message TEXT DEFAULT '')
RETURNS TEXT AS $$
BEGIN
    RETURN ok(got = expected, test_name, test_message || ' (got: ' || got || ', expected: ' || expected || ')');
END;
$$ LANGUAGE plpgsql;

-- Not equal test
CREATE OR REPLACE FUNCTION isnt(got ANYELEMENT, expected ANYELEMENT, test_name TEXT, test_message TEXT DEFAULT '')
RETURNS TEXT AS $$
BEGIN
    RETURN ok(got != expected, test_name, test_message || ' (got: ' || got || ', expected not: ' || expected || ')');
END;
$$ LANGUAGE plpgsql;

-- Comparison test
CREATE OR REPLACE FUNCTION cmp_ok(got ANYELEMENT, op TEXT, expected ANYELEMENT, test_name TEXT, test_message TEXT DEFAULT '')
RETURNS TEXT AS $$
DECLARE
    result BOOLEAN;
BEGIN
    CASE op
        WHEN '>' THEN result := got > expected;
        WHEN '>=' THEN result := got >= expected;
        WHEN '<' THEN result := got < expected;
        WHEN '<=' THEN result := got <= expected;
        WHEN '=' THEN result := got = expected;
        WHEN '!=' THEN result := got != expected;
        ELSE result := FALSE;
    END CASE;
    
    RETURN ok(result, test_name, test_message || ' (got: ' || got || ' ' || op || ' ' || expected || ')');
END;
$$ LANGUAGE plpgsql;

-- Null test
CREATE OR REPLACE FUNCTION is_null(got ANYELEMENT, test_name TEXT, test_message TEXT DEFAULT '')
RETURNS TEXT AS $$
BEGIN
    RETURN ok(got IS NULL, test_name, test_message);
END;
$$ LANGUAGE plpgsql;

-- Not null test
CREATE OR REPLACE FUNCTION isnt_null(got ANYELEMENT, test_name TEXT, test_message TEXT DEFAULT '')
RETURNS TEXT AS $$
BEGIN
    RETURN ok(got IS NOT NULL, test_name, test_message);
END;
$$ LANGUAGE plpgsql;

-- Finish function
CREATE OR REPLACE FUNCTION finish()
RETURNS TABLE(test_name TEXT, test_result TEXT, test_message TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT tr.test_name, tr.test_result, tr.test_message
    FROM test_results tr
    ORDER BY tr.id;
END;
$$ LANGUAGE plpgsql;
