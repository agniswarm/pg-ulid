#
# Makefile - Unix (Linux / macOS) build for PostgreSQL ULID extension
# Ensures libbson/libmongoc headers are discovered via pkg-config or via
# a configurable MONGO_PREFIX fallback and that include flags are added
# to CFLAGS/CPPFLAGS/PG_CFLAGS/PG_CPPFLAGS so clang/gcc and LTO steps see them.
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

# Optional: point to ulid-c include/lib if you want to use it
ULID_C_DIR ?=
ifdef ULID_C_DIR
  ULID_C_INCDIR = -I$(ULID_C_DIR)/include
  ULID_C_LIBDIR = -L$(ULID_C_DIR)/lib
  ULID_C_LIBS   = -lulid
else
  ULID_C_INCDIR =
  ULID_C_LIBDIR =
  ULID_C_LIBS =
endif

# ---------- Mongo C driver detection ----------
# Try pkg-config first (preferred)
PKG_MONGOC_CFLAGS := $(shell pkg-config --cflags libmongoc-1.0 2>/dev/null || echo "")
PKG_MONGOC_LIBS   := $(shell pkg-config --libs libmongoc-1.0 2>/dev/null || echo "")

# Check if pkg-config worked
ifneq ($(PKG_MONGOC_CFLAGS),)
  MONGOC_CFLAGS := $(PKG_MONGOC_CFLAGS)
  MONGOC_LIBS := $(PKG_MONGOC_LIBS)
  MONGOC_AVAILABLE = yes
else
  # Fallback to standard paths
  MONGOC_CFLAGS := -I/usr/include/libbson-1.0 -I/usr/include/libmongoc-1.0
  MONGOC_LIBS := -lmongoc-1.0 -lbson-1.0
  # Check if fallback paths exist
  ifeq ($(wildcard /usr/include/libbson-1.0/bson.h),)
    MONGOC_AVAILABLE = no
    $(warning MongoDB C driver not found. ObjectId support will be disabled.)
  else
    MONGOC_AVAILABLE = yes
  endif
endif

# Conditionally add ObjectId support
ifeq ($(MONGOC_AVAILABLE),yes)
  OBJS += src/objectid.o
  DATA += sql/$(EXTENSION)--$(EXTVERSION)-objectid.sql
endif

# Target arch flags
TARGET_ARCH ?= $(shell uname -m)
ARCH_FLAGS :=
ifeq ($(TARGET_ARCH), i386)
  ARCH_FLAGS += -m32
endif

OPTFLAGS ?= -O2

# Add to PostgreSQL compile flags
# PG_CFLAGS is used by PGXS rules, PG_CPPFLAGS is for preprocessor includes
PG_CFLAGS += $(OPTFLAGS) $(ARCH_FLAGS) -std=gnu11 -fno-lto -fno-fat-lto-objects \
             -Wno-unused-variable -Wno-unused-function

# Make sure include flags are available in every relevant variable so both
# gcc compile and clang LTO/emit-llvm compile steps see them.
# (Some PGXS rules use CPPFLAGS/CFLAGS directly for different compile invocations.)
CPPFLAGS += $(ULID_C_INCDIR)
PG_CPPFLAGS += $(ULID_C_INCDIR)
CFLAGS += $(ULID_C_INCDIR)
PG_CFLAGS += $(ULID_C_INCDIR)

# Add MongoDB flags only if available
ifeq ($(MONGOC_AVAILABLE),yes)
  CPPFLAGS += $(MONGOC_CFLAGS)
  PG_CPPFLAGS += $(MONGOC_CFLAGS)
  CFLAGS += $(MONGOC_CFLAGS)
  PG_CFLAGS += $(MONGOC_CFLAGS)
  SHLIB_LINK += $(MONGOC_LIBS)
endif

# Linker flags
SHLIB_LINK += $(ULID_C_LIBDIR) $(ULID_C_LIBS)

CC ?= $(HOSTCC)

# build rule for object files under src/
src/%.o: src/%.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $(PG_CFLAGS) -c $< -o $@

# Custom installcheck: run our CI script (if present)
installcheck: all
	@echo "Running extension tests via test/build/ci.sh..."
	@echo "Data files: $(DATA)"
	@if [ -f "test/build/ci.sh" ]; then \
		bash test/build/ci.sh; \
	else \
		echo "ERROR: test/build/ci.sh not found"; \
		exit 1; \
	fi

.PHONY: all all-local install installcheck uninstall clean

# include PGXS at the end so variables above are used by PGXS rules
include $(PGXS)
