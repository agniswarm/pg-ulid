# Makefile for ulid extension (Go implementation)

EXTENSION = ulid
VERSION = 1.0.0
DATA = sql/$(EXTENSION)--$(VERSION).sql

# PostgreSQL extension build system
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Directory variables provided by PGXS:
# - bindir : where Postgres binaries live
# - datadir: top-level share directory
# We will install the SQL into $(datadir)/extension to avoid mutating source.

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
# Do not mutate the source SQL file; write the generated SQL into the installed datadir.
install: install-binary
	@echo "Installing SQL to $(DESTDIR)$(datadir)/extension"
	install -d -m 0755 $(DESTDIR)$(datadir)/extension
	# Replace @BINDIR@ placeholder in SQL and install into datadir/extension
	sed "s|@BINDIR@|$(bindir)|g" sql/$(EXTENSION)--$(VERSION).sql \
		> $(DESTDIR)$(datadir)/extension/$(EXTENSION)--$(VERSION).sql
	# Now run the PGXS-provided install target to install control file, etc.
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
