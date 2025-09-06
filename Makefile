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

# Install the binary
install: ulid_generator
	# Create directory and install the Go binary
	mkdir -p $(DESTDIR)/usr/local/bin
	install -m 755 ulid_generator $(DESTDIR)/usr/local/bin/ulid_generator
	# Install extension files manually to the correct location
	mkdir -p $(DESTDIR)/usr/share/postgresql/17/extension
	install -m 644 ulid.control $(DESTDIR)/usr/share/postgresql/17/extension/
	install -m 644 sql/ulid--1.0.0.sql $(DESTDIR)/usr/share/postgresql/17/extension/

# Run tests
test:
	cd test && go test -v

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
