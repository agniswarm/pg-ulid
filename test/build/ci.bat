@echo off
REM Windows CI batch script for ULID extension testing
REM This script runs the Python test suite against the installed extension

echo ========================================
echo ULID Extension CI Test Suite (Windows)
echo ========================================

REM Check if Python is available
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Python is not available in PATH
    echo Please ensure Python is installed and accessible
    exit /b 1
)

REM Check if PostgreSQL is running
echo Checking PostgreSQL connection...
psql --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: psql is not available in PATH
    echo Please ensure PostgreSQL is installed and psql is accessible
    exit /b 1
)

REM Install Python dependencies
echo Installing Python test dependencies...
pip install -r test/requirements.txt
if %errorlevel% neq 0 (
    echo ERROR: Failed to install Python dependencies
    exit /b 1
)

REM Run the Python test suite
echo Running Python test suite...
cd test
python -m pytest -v
if %errorlevel% neq 0 (
    echo ERROR: Python tests failed
    exit /b 1
)

echo ========================================
echo All tests completed successfully!
echo ========================================
