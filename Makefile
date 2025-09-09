#
# Makefile - PostgreSQL ULID extension (production-ready)
#

EXTENSION = ulid
EXTVERSION = 0.3.0
SQL_DIR = sql
ASSEMBLED_DIR = $(SQL_DIR)/assembled

# Base SQL modules (objectid.sql appended conditionally below)
SQL_MODULES = \
  $(SQL_DIR)/00-extensions.sql \
  $(SQL_DIR)/ulid.sql

.PHONY: all assemble clean release installcheck

# C build variables (must be set before including PGXS)
MODULE_big = $(EXTENSION)
OBJS = src/ulid.o

# Ensure `make` builds both the assembled SQL and the shared object
all: assemble $(MODULE_big).so

assemble: $(ASSEMBLED_DIR)/$(EXTENSION)--$(EXTVERSION).sql

$(ASSEMBLED_DIR):
	mkdir -p $(ASSEMBLED_DIR)

# Build assembled SQL by concatenating module files in order
$(ASSEMBLED_DIR)/$(EXTENSION)--$(EXTVERSION).sql: $(SQL_MODULES) | $(ASSEMBLED_DIR)
	@mkdir -p $(ASSEMBLED_DIR)
	@echo "-- Assembled $(EXTENSION)--$(EXTVERSION)" > $@
	@for f in $(SQL_MODULES); do \
	  echo "-- ==== $$f ====" >> $@; \
	  cat $$f >> $@; \
	  echo "" >> $@; \
	done

# Files to install (PGXS uses DATA)
DATA = $(EXTENSION).control $(ASSEMBLED_DIR)/$(EXTENSION)--$(EXTVERSION).sql

#
# Optional MongoDB (ObjectId) support detection
# - Prefer pkg-config; fallback to common system includes.
#
PKG_CONFIG ?= pkg-config

ifneq ($(shell $(PKG_CONFIG) --exists libmongoc-1.0 2>/dev/null && echo yes),)
  PKG_MONGOC_CFLAGS := $(shell $(PKG_CONFIG) --cflags libmongoc-1.0)
  PKG_MONGOC_LIBS   := $(shell $(PKG_CONFIG) --libs   libmongoc-1.0)
endif

ifneq ($(PKG_MONGOC_CFLAGS),)
  MONGOC_CFLAGS := $(PKG_MONGOC_CFLAGS)
  MONGOC_LIBS   := $(PKG_MONGOC_LIBS)
  MONGOC_AVAILABLE = yes
else
  # fallback check for header presence (common Linux layout)
  MONGOC_CFLAGS := -I/usr/include/libbson-1.0 -I/usr/include/libmongoc-1.0
  MONGOC_LIBS   := -lmongoc-1.0 -lbson-1.0

  ifneq ($(wildcard /usr/include/libbson-1.0/bson.h),)
    MONGOC_AVAILABLE = yes
  else
    MONGOC_AVAILABLE = no
    $(warning MongoDB C driver not found. ObjectId support will be disabled.)
  endif
endif

# If libmongoc available, enable objectid.c compilation and include objectid.sql
ifeq ($(MONGOC_AVAILABLE),yes)
  OBJS += src/objectid.o
  SHLIB_LINK += $(MONGOC_LIBS)
  PG_CPPFLAGS += $(MONGOC_CFLAGS)
  SQL_MODULES += $(SQL_DIR)/objectid.sql
endif

# Non-interactive release: `make release RELEASE=0.3.1`
release:
	$(MAKE) clean
	@if [ -z "$(RELEASE)" ]; then \
	  echo "Usage: make release RELEASE=x.y.z"; exit 1; \
	fi
	mkdir -p $(ASSEMBLED_DIR)
	@cat $(SQL_MODULES) > $(ASSEMBLED_DIR)/$(EXTENSION)--$(RELEASE).sql
	@echo "Built $(ASSEMBLED_DIR)/$(EXTENSION)--$(RELEASE).sql"

# Clean (local assembled files) + PGXS clean
clean:
	-rm -rf $(ASSEMBLED_DIR)
	-$(MAKE) -s -f $(PGXS) clean || true

# Installcheck target (optional)
installcheck: all
	@echo "Running installcheck (if configured)..."
	@echo "DATA: $(DATA)"
	@if [ -f "test/build/ci.sh" ]; then \
	  bash test/build/ci.sh; \
	else \
	  echo "No test/build/ci.sh present; skipping."; \
	fi

# --- include PGXS at the end so variables above are used by PGXS rules
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
