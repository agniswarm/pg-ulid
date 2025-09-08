@echo off
REM Windows CI batch script for ULID extension testing
REM This script runs the same tests as ci.sh but adapted for Windows

echo ========================================
echo ULID Extension CI Test Suite (Windows)
echo ========================================

REM Check if PostgreSQL is running
echo Checking PostgreSQL connection...
pg_isready -q >nul 2>&1
if %errorlevel% neq 0 (
    echo PostgreSQL is not running. Attempting to start it...
    net start postgresql-x64-14 >nul 2>&1
    if %errorlevel% neq 0 (
        echo Failed to start PostgreSQL service. Trying alternative service names...
        net start postgresql >nul 2>&1
        if %errorlevel% neq 0 (
            echo ERROR: Cannot start PostgreSQL. This test requires a running PostgreSQL instance.
            echo Please ensure PostgreSQL is installed and the service is running.
            exit /b 1
        )
    )
    echo Waiting for PostgreSQL to start...
    timeout /t 5 >nul
    pg_isready -q >nul 2>&1
    if %errorlevel% neq 0 (
        echo ERROR: PostgreSQL is still not responding after startup attempt.
        exit /b 1
    )
)

REM Use the default postgres database
set PGDATABASE=postgres

REM Test basic extension functionality
echo Creating extension...
psql -c "CREATE EXTENSION IF NOT EXISTS ulid;" 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Failed to create extension.
    exit /b 1
)

echo Testing ulid function...
psql -c "SELECT ulid^();" 2>&1
if %errorlevel% neq 0 (
    echo ERROR: ulid function test failed
    exit /b 1
)

echo Testing ulid_random function...
psql -c "SELECT ulid_random^();" 2>&1
if %errorlevel% neq 0 (
    echo ERROR: ulid_random function test failed
    exit /b 1
)

echo Testing ulid_time function...
psql -c "SELECT ulid_time^(^(extract^(epoch from now^(^)^) * 1000^)::BIGINT^);" 2>&1
if %errorlevel% neq 0 (
    echo ERROR: ulid_time function test failed
    exit /b 1
)

echo Testing ulid_batch function...
psql -c "SELECT array_length^(ulid_batch^(5^), 1^);" 2>&1
if %errorlevel% neq 0 (
    echo ERROR: ulid_batch function test failed
    exit /b 1
)

echo Testing ulid_random_batch function...
psql -c "SELECT array_length^(ulid_random_batch^(3^), 1^);" 2>&1
if %errorlevel% neq 0 (
    echo ERROR: ulid_random_batch function test failed
    exit /b 1
)

echo Testing ulid_parse function...
psql -c "SELECT * FROM ulid_parse^('01K4FQ7QN4ZSW0SG5XACGM2HB4'^);" 2>&1
if %errorlevel% neq 0 (
    echo ERROR: ulid_parse function test failed
    exit /b 1
)

echo Cleaning up...
psql -c "DROP EXTENSION IF EXISTS ulid;" >nul 2>&1

echo ========================================
echo All tests passed successfully!
echo ========================================
