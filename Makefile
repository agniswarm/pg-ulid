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

# for Postgres < 15
PROVE_FLAGS += -I ./test/perl

prove_installcheck:
	rm -rf $(CURDIR)/tmp_check
	cd $(srcdir) && TESTDIR='$(CURDIR)' PATH="$(bindir):$$PATH" PGPORT='6$(DEF_PGPORT)' PG_REGRESS='$(top_builddir)/src/test/regress/pg_regress' $(PROVE) $(PG_PROVE_FLAGS) $(PROVE_FLAGS) $(if $(PROVE_TESTS),$(PROVE_TESTS),test/t/*.pl)

.PHONY: dist

.PHONY: prove_installcheck
