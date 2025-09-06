# Makefile for ulid extension (Go implementation)

EXTENSION = ulid
VERSION ?= 1.0.0
# keep DATA for compatibility but don't rely on it being correct at runtime
DATA = sql/$(EXTENSION)--$(VERSION).sql

# PostgreSQL extension build system
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# find the source SQL file dynamically (pick first matching)
SRC_SQL := $(firstword $(wildcard sql/$(EXTENSION)--*.sql))
SQL_BASENAME := $(notdir $(SRC_SQL))

# Override the default build target
all: ulid_generator

# Build the Go binary
ulid_generator: src/ulid.go
	@echo "Building Go binary..."
	cd src && go mod download
	cd src && go build -o ../ulid_generator .

# Custom install target for the Go binary (respects DESTDIR and bindir)
install-binary: ulid_generator
	@echo "Installing ulid_generator to $(DESTDIR)$(bindir)"
	install -d -m 0755 $(DESTDIR)$(bindir)
	install -m 0755 ulid_generator $(DESTDIR)$(bindir)/ulid_generator

# Install extension files AND the binary.
# Do not mutate the source SQL file; write the substituted SQL into datadir/extension.
install: install-binary
	@echo "Preparing to install SQL..."
	@if [ -z "$(SRC_SQL)" ]; then \
		echo "ERROR: no sql/$(EXTENSION)--*.sql file found in source tree."; \
		echo "       present files:"; ls -la sql || true; \
		exit 2; \
	fi
	@echo "Using source SQL: $(SRC_SQL)"
	install -d -m 0755 $(DESTDIR)$(datadir)/extension
	# Replace @BINDIR@ placeholder in the source SQL and install into datadir/extension
	sed "s|@BINDIR@|$(bindir)|g" "$(SRC_SQL)" > "$(DESTDIR)$(datadir)/extension/$(SQL_BASENAME)"
	# Call PGXS install to put control file, etc., in place
	$(MAKE) -s -f $(top_srcdir)/Makefile install

# Run Go unit tests
test:
	cd test && go test -v ./...

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

# Clean build artifacts
clean:
	rm -f ulid_generator
	cd src && go clean
	cd test && go clean -testcache

.PHONY: all install install-binary test installcheck clean
