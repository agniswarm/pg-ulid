# Makefile for ulid extension (C implementation) - cross-platform (Linux/macOS/Windows)
EXTENSION = ulid
VERSION ?= 0.1.1
DATA = sql/$(EXTENSION)--$(VERSION).sql

# Module / object definitions for PGXS
MODULES = $(EXTENSION)
OBJS = src/ulid.o
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)

# Disable LTO/bitcode to avoid LLVM/clang conflicts on macOS CI images
PG_CPPFLAGS += -fno-lto -fno-fat-lto-objects
PG_CFLAGS += -fno-lto -fno-fat-lto-objects
PG_LDFLAGS += -fno-lto -fno-fat-lto-objects

# Force a stable C compiler invocation (if you must override)
CC ?= gcc

# Include PGXS rules (this defines all / install / installcheck / clean etc.)
ifeq ($(PGXS),)
$(error "pg_config not found or PGXS not available. Ensure PG_CONFIG points to a PostgreSQL pg_config.")
endif
include $(PGXS)

# Custom compile rule for src/ulid.o (ensures flags are honored)
# (PGXS already defines implicit rules; this explicit rule makes the compile command clearer)
src/ulid.o: src/ulid.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

# Install binary into $(bindir) if you also build an external helper binary
# (useful if you have a helper like ulid_generator)
install-binary:
	@echo "install-binary: no-op (add commands to install external binaries if needed)"
	# Example (uncomment and adapt):
	# install -d -m 0755 $(DESTDIR)$(bindir)
	# install -m 0755 ulid_generator $(DESTDIR)$(bindir)/ulid_generator

# install-local: write substituted SQL into datadir/extension without relying on PGXS filename magic
install-local: all
	@echo "install-local: writing SQL/control to $(DESTDIR)$(datadir)/extension and installing binary if present"
	@if [ ! -f "sql/$(EXTENSION)--*.sql" ] && [ ! -f "$(DATA)" ]; then \
		echo "Warning: source SQL file not found; listing sql/: " ; ls -la sql || true ; \
	fi
	install -d -m 0755 $(DESTDIR)$(datadir)/extension
	# find first sql/ulid--*.sql (keeps compatibility with PGXS generated names)
	SRC_SQL=$$(printf "%s\n" sql/$(EXTENSION)--*.sql | sed -n '1p'); \
	if [ -z "$$SRC_SQL" ] || [ "$$SRC_SQL" = "sql/$(EXTENSION)--*.sql" ]; then \
		echo "ERROR: no sql/$(EXTENSION)--*.sql found"; exit 2; \
	fi; \
	SQL_BASENAME=$$(basename "$$SRC_SQL"); \
	sed "s|@BINDIR@|$(bindir)|g" "$$SRC_SQL" > "$(DESTDIR)$(datadir)/extension/$$SQL_BASENAME"; \
	if [ -f "$(EXTENSION).control" ]; then \
		install -m 0644 "$(EXTENSION).control" "$(DESTDIR)$(datadir)/extension/"; \
	else \
		echo "Warning: $(EXTENSION).control not found in repo (install-local will continue)"; \
	fi; \
	echo "install-local: installed $$SQL_BASENAME to $(DESTDIR)$(datadir)/extension/"

# Keep the usual targets; PGXS provides: all, install, installcheck, clean, dist, etc.
# We only add convenience targets above.

.PHONY: install-local install-binary
