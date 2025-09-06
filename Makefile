# Makefile for ulid extension (Go implementation)

EXTENSION = ulid
DATA = sql/ulid--1.0.0.sql

# PostgreSQL extension build system
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Override the default build target
all: ulid_generator

# Build the Go binary
ulid_generator: src/ulid.go
	cd src && go mod download
	cd src && go build -o ../ulid_generator ulid.go

# Custom install target for the Go binary
install-binary: ulid_generator
	# Create directory and install the Go binary to bindir
	mkdir -p $(DESTDIR)$(bindir)
	install -m 755 ulid_generator $(DESTDIR)$(bindir)/ulid_generator

# Override the default install to include our binary
install: install-binary
	# Replace @BINDIR@ placeholder in SQL file with actual bindir
	sed "s|@BINDIR@|$(bindir)|g" sql/ulid--1.0.0.sql > sql/ulid--1.0.0.sql.tmp
	mv sql/ulid--1.0.0.sql.tmp sql/ulid--1.0.0.sql

# Run tests
test:
	cd test && go test -v

# PostgreSQL regression tests (requires PostgreSQL to be running)
installcheck:
	@echo "Running PostgreSQL extension tests..."
	@if ./test/build/ci.sh; then \
		echo "Extension tests passed!"; \
	else \
		echo "Extension tests failed or PostgreSQL not available."; \
		echo "In CI, PostgreSQL should be running. Locally, start PostgreSQL first."; \
		exit 1; \
	fi


# Run comprehensive test suite
test-all: test
	./test/run_tests_go.sh

# Run tests with verbose output
test-verbose: test
	./test/run_tests_go.sh -v

# Run tests without database integration
test-no-db: test
	./test/run_tests_go.sh --skip-db

# Clean build artifacts
clean:
	rm -f ulid_generator
	cd test && go clean -testcache

# Help target
help:
	@echo Available targets:
	@echo   all         - Build the extension (default)
	@echo   install     - Install the extension
	@echo   test        - Run Go unit tests
	@echo   test-all    - Run comprehensive test suite
	@echo   test-verbose- Run tests with verbose output
	@echo   test-no-db  - Run tests without database integration
	@echo   clean       - Clean build artifacts
	@echo   help        - Show this help message

.PHONY: all install test test-all test-verbose test-no-db clean help
