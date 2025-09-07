# Makefile for ulid extension (C implementation)

EXTENSION = ulid
VERSION ?= 0.1.1
DATA = sql/$(EXTENSION)--$(VERSION).sql


# C extension
MODULE_big = ulid
OBJS = src/ulid.o

# PostgreSQL configuration
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)

# Disable bitcode generation to avoid LLVM version conflicts
PG_CPPFLAGS += -fno-lto -fno-fat-lto-objects
PG_CFLAGS += -fno-lto -fno-fat-lto-objects
PG_LDFLAGS += -fno-lto -fno-fat-lto-objects

# Use system gcc by default
CC ?= gcc

# Force disable LTO at the makefile level
override CFLAGS += -fno-lto -fno-fat-lto-objects
override LDFLAGS += -fno-lto -fno-fat-lto-objects

# find the source SQL file dynamically (pick first matching)
SRC_SQL := $(firstword $(wildcard sql/$(EXTENSION)--*.sql))
SQL_BASENAME := $(notdir $(SRC_SQL))

include $(PGXS)

all: $(MODULE_big).so

# build the object if needed (PGXS usually handles it; keep explicit rule for src/ulid.o)
src/ulid.o: src/ulid.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

clean:
	rm -f src/*.o
	rm -f src/*.bc
	rm -f $(MODULE_big).so
	rm -f $(MODULE_big).dll
	rm -f $(MODULE_big).dylib
	rm -f regression.diffs
	rm -f regression.out

# ---------- Robust install-local ----------
# Install extension files into datadir/extension and copy shared lib into pkglibdir
install-local: all
	@echo "Running install-local (manual safe install)..."
	@if [ -z "$(SRC_SQL)" ]; then \
		echo "ERROR: no sql/$(EXTENSION)--*.sql file found in source tree."; \
		echo "Present files in sql/:"; ls -la sql || true; \
		exit 2; \
	fi
	@echo "Using source SQL: $(SRC_SQL)"
	@echo "Installing server library to $(DESTDIR)$(pkglibdir)"
	install -d -m 0755 $(DESTDIR)$(pkglibdir)
	install -m 0755 $(MODULE_big).so $(DESTDIR)$(pkglibdir)/$(MODULE_big).so
	@echo "Installing control + SQL to $(DESTDIR)$(datadir)/extension"
	install -d -m 0755 $(DESTDIR)$(datadir)/extension
	# copy control file if present
	if [ -f "$(EXTENSION).control" ]; then \
		install -m 0644 "$(EXTENSION).control" "$(DESTDIR)$(datadir)/extension/"; \
	else \
		echo "Warning: $(EXTENSION).control not found in repo"; \
	fi
	# replace @BINDIR@ in source SQL (if present) and write to datadir extension dir
	sed "s|@BINDIR@|$(bindir)|g" "$(SRC_SQL)" > "$(DESTDIR)$(datadir)/extension/$(notdir $(SRC_SQL))"
	@echo "install-local completed."

# Keep the normal PGXS install available (for local developers who want to use make install)
.PHONY: install-local all clean

# Run Go unit tests (if any)
test:
	@echo "No Go tests configured; skipping."

# PostgreSQL regression tests (useful wrapper)
installcheck:
	@echo "Running PostgreSQL extension tests (installcheck)..."
	@if ./test/build/ci.sh; then \
		echo "Extension tests passed!"; \
	else \
		echo "Extension tests failed or PostgreSQL not available."; \
		echo "In CI, PostgreSQL should be running. Locally, start PostgreSQL first."; \
		exit 1; \
	fi

.PHONY: installcheck test
