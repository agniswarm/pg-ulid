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
.PHONY: install-local install-binary all ulid_generator test installcheck clean prove_installcheck

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

# Run Perl TAP tests using prove (recursive + pgvector-compatible)
PROVE ?= prove
PROVE_FLAGS ?=
PG_PROVE_FLAGS ?=
PROVE_TESTS ?=

prove_installcheck:
	@echo "Running prove_installcheck..."
	@echo "Detecting test files (recursive search)..."
	@echo "  - looking under: test/t, test/perl (recursive), test"
	# If Postgres pg_regress helper exists, prefer the pgvector-style invocation
	@if [ -f "$(top_builddir)/src/test/regress/pg_regress" ]; then \
		echo "Detected Postgres source pg_regress at $(top_builddir)/src/test/regress/pg_regress"; \
		rm -rf $(CURDIR)/tmp_check || true; \
		cd $(srcdir) && \
		TESTDIR='$(CURDIR)' PATH="$(bindir):$$PATH" PGPORT='6$(DEF_PGPORT)' PG_REGRESS='$(top_builddir)/src/test/regress/pg_regress' \
			$(PROVE) $(PG_PROVE_FLAGS) $(PROVE_FLAGS) $(if $(PROVE_TESTS),$(PROVE_TESTS),test/t/*.pl); \
	else \
		# Fallback: recursive discovery of test files
		FOUND=""; \
		# If PROVE_TESTS is provided, validate those files exist
		if [ -n "$(PROVE_TESTS)" ]; then \
			echo "PROVE_TESTS explicitly provided: $(PROVE_TESTS)"; \
			TEST_OK=0; \
			for f in $(PROVE_TESTS); do if [ -f "$$f" ]; then TEST_OK=1; fi; done; \
			if [ $$TEST_OK -eq 0 ]; then \
				echo "PROVE_TESTS provided but no matching files found: $(PROVE_TESTS)"; \
				exit 2; \
			fi; \
			FOUND="$(PROVE_TESTS)"; \
		else \
			# search candidate locations recursively for .t and .pl files
			if command -v find >/dev/null 2>&1; then \
				FOUND=$$(find test/perl test -type f \( -name '*.t' -o -name '*.pl' \) 2>/dev/null || true); \
				if [ -z "$$FOUND" ]; then \
					FOUND=$$(find test/t -type f -name '*.pl' 2>/dev/null || true); \
				fi; \
			else \
				# fallback to non-recursive checks if find not available
				if ls test/perl/*.t >/dev/null 2>&1 || ls test/perl/*.pl >/dev/null 2>&1; then \
					FOUND=$$(ls test/perl/*.t 2>/dev/null || true; ls test/perl/*.pl 2>/dev/null || true); \
				elif ls test/*.t >/dev/null 2>&1 || ls test/*.pl >/dev/null 2>&1; then \
					FOUND=$$(ls test/*.t 2>/dev/null || true; ls test/*.pl 2>/dev/null || true); \
				elif ls test/t/*.pl >/dev/null 2>&1; then \
					FOUND=$$(ls test/t/*.pl 2>/dev/null || true); \
				fi; \
			fi; \
		fi; \
		if [ -z "$$FOUND" ]; then \
			echo "No test files found (searched recursively under test/perl and test). Skipping prove_installcheck."; \
			exit 0; \
		fi; \
		# ensure prove exists
		if ! command -v $(PROVE) >/dev/null 2>&1; then \
			echo "Error: '$(PROVE)' not found. Install Perl TAP tools (on Debian/Ubuntu: apt-get install perl)"; \
			exit 2; \
		fi; \
		echo "Found test files:"; \
		echo "$$FOUND" | sed 's/^/  - /'; \
		EXTRA_I_FLAGS="-I ./postgres/src/test/perl -I ./test/perl -I ./test -I ./"; \
		echo "Running: $(PROVE) $$EXTRA_I_FLAGS $(PROVE_FLAGS) [file list]"; \
		# pass the discovered file list to prove
		printf '%s\n' "$$FOUND" | xargs $(PROVE) $$EXTRA_I_FLAGS $(PROVE_FLAGS); \
	fi

.PHONY: prove_installcheck
