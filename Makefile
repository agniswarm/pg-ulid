# Makefile for ulid extension (C implementation)

EXTENSION = ulid
VERSION ?= 0.1.1
DATA = sql/$(EXTENSION)--$(VERSION).sql


# C extension
MODULE_big = ulid
OBJS = src/ulid.o

# PostgreSQL configuration
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)

# Disable bitcode generation to avoid LLVM version conflicts
# Force regular object file compilation instead of bitcode
PG_CPPFLAGS += -fno-lto -fno-fat-lto-objects
PG_CFLAGS += -fno-lto -fno-fat-lto-objects
PG_LDFLAGS += -fno-lto -fno-fat-lto-objects

# Override compilation to force regular object files
CC = gcc

# Force disable LTO at the makefile level
override CFLAGS += -fno-lto -fno-fat-lto-objects
override LDFLAGS += -fno-lto -fno-fat-lto-objects

include $(PGXS)

# Override the object file compilation to ensure regular .o files
src/ulid.o: src/ulid.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

# Clean targets
clean:
	rm -f src/*.o
	rm -f src/*.bc
	rm -f $(MODULE_big).so
	rm -f $(MODULE_big).dll
	rm -f $(MODULE_big).dylib
	rm -f regression.diffs
	rm -f regression.out

# Install-local target (for CI compatibility)
install-local: all
	$(MAKE) -C . install

# Test target
installcheck: all
	$(MAKE) -C . install
	$(MAKE) -C . installcheck-local

installcheck-local:
	@echo "Testing ULID extension..."
	@if command -v psql >/dev/null 2>&1; then \
		echo "CREATE EXTENSION ulid;" | psql -d postgres; \
		echo "SELECT ulid();" | psql -d postgres; \
		echo "SELECT '01ARZ3NDEKTSV4RRFFQ69G5FAV'::ulid;" | psql -d postgres; \
		echo "SELECT ulid()::timestamp;" | psql -d postgres; \
		echo "SELECT '2023-09-15 12:00:00'::timestamp::ulid;" | psql -d postgres; \
		echo "DROP EXTENSION ulid;" | psql -d postgres; \
	else \
		echo "psql not found - tests skipped"; \
	fi

# Run comprehensive SQL tests (like CI scripts)
test-sql: all
	@echo "Running comprehensive SQL tests..."
	@if command -v psql >/dev/null 2>&1; then \
		psql -c "CREATE DATABASE testdb;" || echo "testdb already exists"; \
		psql -d testdb -c "CREATE EXTENSION IF NOT EXISTS ulid;"; \
		psql -d testdb -f test/sql/pgtap_functions.sql; \
		for test_file in test/sql/*.sql; do \
			if [ "$$(basename $$test_file)" != "pgtap_functions.sql" ]; then \
				echo "Running $$test_file..."; \
				psql -d testdb -f "$$test_file"; \
			fi; \
		done; \
		psql -c "DROP DATABASE IF EXISTS testdb;"; \
	else \
		echo "psql not found - SQL tests skipped"; \
	fi

# Run comprehensive tests using Docker
test-docker:
	@echo "Running comprehensive tests using Docker..."
	@if command -v docker >/dev/null 2>&1; then \
		docker build -t pg-ulid-test . && \
		docker run --rm -d --name pg-ulid-test pg-ulid-test && \
		sleep 5 && \
		docker exec pg-ulid-test psql -U postgres -d testdb -c "CREATE EXTENSION ulid;" && \
		docker exec pg-ulid-test psql -U postgres -d testdb -f /tmp/test_sql/pgtap_functions.sql && \
		for test_file in test/sql/*.sql; do \
			if [ "$$(basename $$test_file)" != "pgtap_functions.sql" ]; then \
				echo "Running $$test_file..."; \
				docker cp $$test_file pg-ulid-test:/tmp/test_sql/; \
				docker exec pg-ulid-test psql -U postgres -d testdb -f /tmp/test_sql/$$(basename $$test_file); \
			fi; \
		done && \
		docker stop pg-ulid-test; \
	else \
		echo "Docker not found - comprehensive tests skipped"; \
	fi

# Run specific test file
test-file:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make test-file FILE=test/sql/01_basic_functionality.sql"; \
		exit 1; \
	fi
	@echo "Running test file: $(FILE)"
	@if command -v docker >/dev/null 2>&1; then \
		docker build -t pg-ulid-test . && \
		docker run --rm -d --name pg-ulid-test pg-ulid-test && \
		sleep 5 && \
		docker exec pg-ulid-test psql -U postgres -d testdb -c "CREATE EXTENSION ulid;" && \
		docker exec pg-ulid-test psql -U postgres -d testdb -f /tmp/test_sql/pgtap_functions.sql && \
		docker cp $(FILE) pg-ulid-test:/tmp/test_sql/ && \
		docker exec pg-ulid-test psql -U postgres -d testdb -f /tmp/test_sql/$$(basename $(FILE)) && \
		docker stop pg-ulid-test; \
	else \
		echo "Docker not found - test skipped"; \
	fi

# Help target
help:
	@echo "Available targets:"
	@echo "  all              - Build the extension (default)"
	@echo "  install          - Install the extension"
	@echo "  install-local    - Install the extension (CI compatibility)"
	@echo "  installcheck     - Run basic extension tests"
	@echo "  test-sql         - Run comprehensive SQL test suite"
	@echo "  test-docker      - Run comprehensive tests using Docker"
	@echo "  test-file        - Run specific test file (FILE=path required)"
	@echo "  clean            - Clean build artifacts"
	@echo "  help             - Show this help message"

.PHONY: all install install-local installcheck installcheck-local test-sql test-docker test-file clean help
