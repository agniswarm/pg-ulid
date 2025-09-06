# Makefile for ulid extension (Go implementation)

EXTENSION = ulid
VERSION ?= 1.0.0
DATA = sql/$(EXTENSION)--$(VERSION).sql

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

SRC_SQL := $(firstword $(wildcard sql/$(EXTENSION)--*.sql))
SQL_BASENAME := $(notdir $(SRC_SQL))
CONTROL_FILE := $(EXTENSION).control

all: ulid_generator

ulid_generator: src/ulid.go
	@echo "Building Go binary..."
	cd src && go mod download
	cd src && go build -o ../ulid_generator .

install-binary: ulid_generator
	@echo "Installing ulid_generator to $(DESTDIR)$(bindir)"
	install -d -m 0755 $(DESTDIR)$(bindir)
	install -m 0755 ulid_generator $(DESTDIR)$(bindir)/ulid_generator

# New: install-local — safe, non-PGXS install that writes control+sql and binary
install-local: install-binary
	@echo "Preparing to install extension files (install-local)..."
	@if [ -z "$(SRC_SQL)" ]; then \
		echo "ERROR: no sql/$(EXTENSION)--*.sql file found in source tree."; \
		echo "Present files:"; ls -la sql || true; \
		exit 2; \
	fi
	@echo "Using source SQL: $(SRC_SQL)"
	install -d -m 0755 $(DESTDIR)$(datadir)/extension
	# write the substituted SQL into datadir/extension
	sed "s|@BINDIR@|$(bindir)|g" "$(SRC_SQL)" > "$(DESTDIR)$(datadir)/extension/$(SQL_BASENAME)"
	# install control file (copy from repo to datadir/extension)
	if [ -f "$(CONTROL_FILE)" ]; then \
		install -m 0644 "$(CONTROL_FILE)" "$(DESTDIR)$(datadir)/extension/$(CONTROL_FILE)"; \
	else \
		echo "Warning: control file '$(CONTROL_FILE)' not found in repo (install-local will continue)"; \
	fi
	@echo "install-local completed: binary -> $(DESTDIR)$(bindir), files -> $(DESTDIR)$(datadir)/extension/"

# Legacy install left alone (do not override PGXS's install target)
.PHONY: install-local install-binary all ulid_generator test installcheck clean

# Run Go unit tests
test:
	cd test && go test -v ./...

installcheck:
	@echo "Running PostgreSQL extension tests..."
	@if ./test/build/ci.sh; then \
		echo "Extension tests passed!"; \
	else \
		echo "Extension tests failed or PostgreSQL not available."; \
		echo "In CI, PostgreSQL should be running. Locally, start PostgreSQL first."; \
		exit 1; \
	fi

clean:
	rm -f ulid_generator
	cd src && go clean
	cd test && go clean -testcache

# Run Perl TAP tests using prove (portable target)
# Usage:
#   make prove_installcheck
#   make prove_installcheck PROVE_FLAGS="-I ./postgres/src/test/perl -v"
prove_installcheck:
	@echo "Running prove_installcheck..."
	@# locate prove
	@command -v prove >/dev/null 2>&1 || (echo "Error: 'prove' not found. Install perl TAP tools (on Debian/Ubuntu: apt-get install perl)"; exit 2)
	@# find test files: prefer repo test/perl, fallback to postgres test dir if present
	@TEST_DIR=""
	@if [ -d "./test/perl" ]; then \
		TEST_DIR="./test/perl"; \
	elif [ -d "./postgres/src/test/perl" ]; then \
		TEST_DIR="./postgres/src/test/perl"; \
	else \
		echo "Error: no Perl test directory found (expected ./test/perl or ./postgres/src/test/perl)"; exit 3; \
	fi; \
	echo "Using TEST_DIR=$$TEST_DIR"; \
	echo "PROVE_FLAGS='$(PROVE_FLAGS)'"; \
	# run prove on all .t files in test dir (if none found, fail)
	set -e; \
	TFILES=$$(ls $$TEST_DIR/*.t 2>/dev/null || true); \
	if [ -z "$$TFILES" ]; then \
		echo "No .t files found in $$TEST_DIR; nothing to run."; exit 4; \
	fi; \
	# prepend -I paths if not already in PROVE_FLAGS
	EXTRA_I_FLAGS="-I ./postgres/src/test/perl -I ./test/perl"; \
	echo "Running: prove $$EXTRA_I_FLAGS $(PROVE_FLAGS) $$TFILES"; \
	prove $$EXTRA_I_FLAGS $(PROVE_FLAGS) $$TFILES

.PHONY: prove_installcheck
