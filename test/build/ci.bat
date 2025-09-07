@echo off
REM Standalone PostgreSQL Extension Test Script for Windows
REM This can be run without the Makefile and PostgreSQL build system

echo Running PostgreSQL extension tests...

REM Check if PostgreSQL is running
pg_isready >nul 2>&1
if errorlevel 1 (
    echo PostgreSQL is not running. This test requires a running PostgreSQL instance.
    echo In CI, PostgreSQL should be started by the CI environment.
    echo Locally, start PostgreSQL with: net start postgresql
    exit /b 1
)

REM Use the default postgres database
set PGDATABASE=postgres

REM Test basic extension functionality
echo Creating extension...
psql -c "CREATE EXTENSION IF NOT EXISTS ulid;"
if errorlevel 1 (
    echo ERROR: Failed to create extension. Make sure it's properly installed.
    echo Check that the extension files are in the correct location:
    echo   - /usr/share/postgresql/*/extension/ulid.control
    echo   - /usr/share/postgresql/*/extension/ulid--1.0.0.sql
    exit /b 1
)

echo Testing ulid() function...
psql -c "SELECT ulid();"
if errorlevel 1 (
    echo ERROR: ulid() function test failed
    exit /b 1
)

echo Testing ulid_random() function...
psql -c "SELECT ulid_random();"
if errorlevel 1 (
    echo ERROR: ulid_random() function test failed
    exit /b 1
)

echo Testing ulid_time() function...
psql -c "SELECT ulid_time((extract(epoch from now()) * 1000)::BIGINT);"
if errorlevel 1 (
    echo ERROR: ulid_time() function test failed
    exit /b 1
)

echo Testing ulid_batch() function...
psql -c "SELECT array_length(ulid_batch(5), 1);"
if errorlevel 1 (
    echo ERROR: ulid_batch() function test failed
    exit /b 1
)

echo Testing ulid_random_batch() function...
psql -c "SELECT array_length(ulid_random_batch(3), 1);"
if errorlevel 1 (
    echo ERROR: ulid_random_batch() function test failed
    exit /b 1
)

echo Testing ulid_parse() function...
psql -c "SELECT * FROM ulid_parse('01K4FQ7QN4ZSW0SG5XACGM2HB4');"
if errorlevel 1 (
    echo ERROR: ulid_parse() function test failed
    exit /b 1
)

echo Cleaning up...
psql -c "DROP EXTENSION IF EXISTS ulid;"

echo All tests passed successfully!
