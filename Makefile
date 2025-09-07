# Makefile for ulid extension (C implementation) - cross-platform (Linux/macOS)
EXTENSION = ulid
VERSION ?= 0.1.1
DATA = $(firstword $(wildcard sql/$(EXTENSION)--*.sql))

# Module / object definitions for PGXS
MODULES = $(EXTENSION)
OBJS = src/ulid.o
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)

# Avoid LTO to prevent macOS clang/LLVM bitcode issues
PG_CPPFLAGS += -fno-lto -fno-fat-lto-objects
PG_CFLAGS   += -fno-lto -fno-fat-lto-objects
PG_LDFLAGS  += -fno-lto -fno-fat-lto-objects

# Let PGXS handle suffixes and platform differences
ifeq ($(PGXS),)
$(error "pg_config not found or PGXS not available. Ensure PG_CONFIG points to a PostgreSQL pg_config.")
endif
include $(PGXS)

# Explicit compile rule for clarity (PGXS would also provide one)
src/ulid.o: src/ulid.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

# Install binary into $(bindir) if you build a helper binary (no-op by default)
install-binary:
	@echo "install-binary: no helper binary to install by default (add commands if needed)"

# install-local: write substituted SQL into datadir/extension without relying on PGXS-generated filename
install-local: all
	@echo "install-local: installing SQL/control to $(DESTDIR)$(datadir)/extension"
	@if [ -z "$(DATA)" ]; then \
		echo "ERROR: no sql/$(EXTENSION)--*.sql file found; listing sql/: " ; ls -la sql || true ; \
		exit 2; \
	fi
	install -d -m 0755 $(DESTDIR)$(datadir)/extension
	sed "s|@BINDIR@|$(bindir)|g" "$(DATA)" > "$(DESTDIR)$(datadir)/extension/$(notdir $(DATA))"
	if [ -f "$(EXTENSION).control" ]; then \
	  install -m 0644 "$(EXTENSION).control" "$(DESTDIR)$(datadir)/extension/"; \
	else \
	  echo "Warning: $(EXTENSION).control not found in repo (install-local continues)"; \
	fi
	@echo "install-local: done"

.PHONY: install-local install-binary
