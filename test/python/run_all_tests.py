#!/usr/bin/env python3
"""
Main test runner for all ULID extension tests
"""

import sys
import os
import subprocess
import time

def run_test(test_file):
    """Run a single test file"""
    print(f"\n{'='*80}")
    print(f"Running {test_file}")
    print(f"{'='*80}")
    
    start_time = time.time()
    try:
        result = subprocess.run([sys.executable, test_file], capture_output=True, text=True, timeout=300)
        end_time = time.time()
        
        if result.returncode == 0:
            print(f"✅ {test_file} PASSED ({end_time - start_time:.2f}s)")
            return True
        else:
            print(f"❌ {test_file} FAILED ({end_time - start_time:.2f}s)")
            print("STDOUT:", result.stdout)
            print("STDERR:", result.stderr)
            return False
    except subprocess.TimeoutExpired:
        print(f"⏰ {test_file} TIMEOUT (300s)")
        return False
    except Exception as e:
        print(f"💥 {test_file} ERROR: {e}")
        return False

def main():
    """Run all tests"""
    print("🚀 Starting ULID Extension Test Suite")
    print("=" * 80)
    
    # List of all test files
    test_files = [
        "test_01_basic_functionality.py",
        "test_02_casting_operations.py", 
        "test_03_monotonic_generation.py",
        "test_04_stress_tests.py",
        "test_05_binary_storage.py",
        "test_06_database_operations.py",
        "test_07_readme_functionality.py",
        "test_08_error_handling.py"
    ]
    
    # Change to the test directory
    test_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(test_dir)
    
    # Run all tests
    passed = 0
    failed = 0
    total_start_time = time.time()
    
    for test_file in test_files:
        if run_test(test_file):
            passed += 1
        else:
            failed += 1
    
    total_end_time = time.time()
    total_duration = total_end_time - total_start_time
    
    # Summary
    print(f"\n{'='*80}")
    print("📊 TEST SUMMARY")
    print(f"{'='*80}")
    print(f"Total Tests: {len(test_files)}")
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    print(f"Total Duration: {total_duration:.2f}s")
    
    if failed == 0:
        print("\n🎉 ALL TESTS PASSED!")
        return 0
    else:
        print(f"\n💥 {failed} TESTS FAILED!")
        return 1

if __name__ == "__main__":
    sys.exit(main())
