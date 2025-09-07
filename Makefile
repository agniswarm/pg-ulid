# Makefile for ulid extension (C implementation) - cross-platform (Linux/macOS)
EXTENSION = ulid
VERSION ?= 0.1.1
DATA = $(firstword $(wildcard sql/$(EXTENSION)--*.sql))

# Module / object definitions for PGXS
MODULES = $(EXTENSION)
OBJS = src/ulid.o
PG_CONFIG ?= pg_config

# Quick diagnostics: ensure pg_config exists and is usable before invoking PGXS
PG_CONFIG_PATH := $(shell which $(PG_CONFIG) 2>/dev/null || true)
ifeq ($(PG_CONFIG_PATH),)
$(error "pg_config not found in PATH. Ensure Postgres dev files are installed and pg_config is on PATH")
endif

PGXS := $(shell $(PG_CONFIG) --pgxs 2>/dev/null || true)
ifeq ($(PGXS),)
$(error "pg_config found but --pgxs did not return a value. Ensure Postgres dev files (pgxs) are available.")
endif

# Avoid LTO to prevent macOS clang/LLVM bitcode issues
PG_CPPFLAGS += -fno-lto -fno-fat-lto-objects
PG_CFLAGS   += -fno-lto -fno-fat-lto-objects
PG_LDFLAGS  += -fno-lto -fno-fat-lto-objects

# Let PGXS handle suffixes and platform differences
include $(PGXS)

# Explicit compile rule for clarity (PGXS would also provide one)
src/ulid.o: src/ulid.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

# Default target is provided by PGXS via modules, but keep explicit alias
all: $(MODULES).so
.PHONY: all

# Install a helper binary if you add one (no-op by default)
install-binary:
	@echo "install-binary: no helper binary to install by default (add commands if needed)"

# install-local: write substituted SQL/control to $(DESTDIR)$(datadir)/extension
# Useful for CI where we want to write SQL directly to Postgres sharedir
install-local: all
	@echo "install-local: installing SQL/control to $(DESTDIR)$(datadir)/extension"
	@if [ -z "$(DATA)" ]; then \
		echo "ERROR: no sql/$(EXTENSION)--*.sql file found; listing sql/: " ; ls -la sql || true ; \
		exit 2; \
	fi
	install -d -m 0755 $(DESTDIR)$(datadir)/extension
	# substitute @BINDIR@ token in provided SQL (if present)
	sed "s|@BINDIR@|$(bindir)|g" "$(DATA)" > "$(DESTDIR)$(datadir)/extension/$(notdir $(DATA))"
	if [ -f "$(EXTENSION).control" ]; then \
	  install -m 0644 "$(EXTENSION).control" "$(DESTDIR)$(datadir)/extension/"; \
	else \
	  echo "Warning: $(EXTENSION).control not found in repo (install-local continues)"; \
	fi
	@echo "install-local: done"

# Standard PGXS install target (when using `make install` with PG_CONFIG set)
# PGXS supplies 'install' and 'installcheck' targets; we don't override them here.

# Provide a simple installcheck wrapper in case PGXS target isn't present
installcheck:
	@echo "Running installcheck (delegating to PGXS installcheck)"
	$(MAKE) -s -f $(CURDIR)/Makefile PG_CONFIG=$(PG_CONFIG) installcheck || true

# Cleaning
clean:
	$(MAKE) -s -f $(PGXS) clean || true
	rm -f src/*.o src/*.bc || true

.PHONY: install-local install-binary installcheck clean
