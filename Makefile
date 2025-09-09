#
# Makefile - Unix (Linux / macOS) build for PostgreSQL ULID extension
# Requires libbson/libmongoc development libraries
#

EXTENSION = ulid
EXTVERSION = 0.2.0

MODULE_big = $(EXTENSION)
OBJS = src/ulid.o src/objectid.o
DATA = $(EXTENSION).control sql/$(EXTENSION)--$(EXTVERSION).sql
REGRESS =

# pg_config used to find PGXS
PG_CONFIG ?= pg_config

PG_CONFIG_PATH := $(shell which $(PG_CONFIG) 2>/dev/null || true)
ifeq ($(PG_CONFIG_PATH),)
$(error pg_config not found in PATH. Please install PostgreSQL development packages or set PG_CONFIG)
endif

PGXS := $(shell $(PG_CONFIG) --pgxs 2>/dev/null || true)
ifeq ($(PGXS),)
$(error PGXS not available from pg_config ($(PG_CONFIG)). Please ensure PostgreSQL development files are installed.)
endif

# Try pkg-config first (preferred)
PKG_MONGOC_CFLAGS := $(shell pkg-config --cflags libmongoc-1.0 2>/dev/null || echo "")
PKG_MONGOC_LIBS   := $(shell pkg-config --libs libmongoc-1.0 2>/dev/null || echo "")

# Check if pkg-config worked
ifneq ($(PKG_MONGOC_CFLAGS),)
  MONGOC_CFLAGS := $(PKG_MONGOC_CFLAGS)
  MONGOC_LIBS := $(PKG_MONGOC_LIBS)
else
  # Fallback to standard paths
  MONGOC_CFLAGS := -I/usr/include/libbson-1.0 -I/usr/include/libmongoc-1.0
  MONGOC_LIBS := -lmongoc-1.0 -lbson-1.0
endif

# Verify MongoDB C driver is available
CHECK_MONGOC := $(shell echo "$(MONGOC_CFLAGS)" | grep -q "include" && echo "yes" || echo "no")
ifeq ($(CHECK_MONGOC),no)
$(error MongoDB C driver not found. Please install libmongoc-dev and libbson-dev packages)
endif

# Target arch flags
TARGET_ARCH ?= $(shell uname -m)
ARCH_FLAGS :=
ifeq ($(TARGET_ARCH), i386)
  ARCH_FLAGS += -m32
endif

OPTFLAGS ?= -O2

# Add to PostgreSQL compile flags
PG_CFLAGS += $(OPTFLAGS) $(ARCH_FLAGS) -std=gnu11 -fno-lto -fno-fat-lto-objects \
              -Wno-unused-variable -Wno-unused-function

# Add MongoDB flags
CPPFLAGS += $(MONGOC_CFLAGS)
PG_CPPFLAGS += $(MONGOC_CFLAGS)
CFLAGS += $(MONGOC_CFLAGS)
PG_CFLAGS += $(MONGOC_CFLAGS)

# Linker flags
SHLIB_LINK += $(MONGOC_LIBS)

CC ?= $(HOSTCC)

# build rule for object files under src/
src/%.o: src/%.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $(PG_CFLAGS) -c $< -o $@

# Custom installcheck: run our CI script (if present)
installcheck: all
	@echo "Running extension tests via test/build/ci.sh..."
	@if [ -f "test/build/ci.sh" ]; then \
		bash test/build/ci.sh; \
	else \
		echo "ERROR: test/build/ci.sh not found"; \
		exit 1; \
	fi

.PHONY: all all-local install installcheck uninstall clean

# include PGXS at the end so variables above are used by PGXS rules
include $(PGXS)
