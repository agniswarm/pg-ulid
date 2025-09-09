#
# Makefile - PostgreSQL ULID extension with optional ObjectId support
# Based on pgvector's build system with conditional MongoDB support
#

EXTENSION = ulid
EXTVERSION = 0.2.0

MODULE_big = $(EXTENSION)
OBJS = src/ulid.o
DATA = $(EXTENSION).control sql/$(EXTENSION)--$(EXTVERSION).sql

# Regression testing disabled - use manual testing instead
# TESTS = $(wildcard test/sql/*.sql)
# REGRESS = $(patsubst test/sql/%.sql,%,$(TESTS))
# REGRESS_OPTS = --inputdir=test --load-extension=$(EXTENSION)

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

# ---------- MongoDB C driver detection ----------
# Try pkg-config first (preferred - should work after CI installation)
PKG_MONGOC_CFLAGS := $(shell pkg-config --cflags libmongoc-1.0 2>/dev/null || echo "")
PKG_MONGOC_LIBS   := $(shell pkg-config --libs libmongoc-1.0 2>/dev/null || echo "")

# Check if pkg-config worked
ifneq ($(PKG_MONGOC_CFLAGS),)
  MONGOC_CFLAGS := $(PKG_MONGOC_CFLAGS)
  MONGOC_LIBS := $(PKG_MONGOC_LIBS)
  MONGOC_AVAILABLE = yes
else
  # Fallback: simple check for standard locations
  # CI should install libraries in standard locations
  MONGOC_CFLAGS := -I/usr/include/libbson-1.0 -I/usr/include/libmongoc-1.0
  MONGOC_LIBS := -lmongoc-1.0 -lbson-1.0
  
  # Simple check - if header exists, assume libraries are available
  ifneq ($(wildcard /usr/include/libbson-1.0/bson.h),)
    MONGOC_AVAILABLE = yes
  else
    MONGOC_AVAILABLE = no
    $(warning MongoDB C driver not found. ObjectId support will be disabled.)
  endif
endif

# Conditionally add ObjectId support
ifeq ($(MONGOC_AVAILABLE),yes)
  OBJS += src/objectid.o
endif

# Target arch flags
TARGET_ARCH ?= $(shell uname -m)
ARCH_FLAGS :=
ifeq ($(TARGET_ARCH), i386)
  ARCH_FLAGS += -m32
endif

# To compile for portability, run: make OPTFLAGS=""
OPTFLAGS ?= -O2

# Mac ARM doesn't always support -march=native
ifeq ($(shell uname -s), Darwin)
	ifeq ($(shell uname -p), arm)
		# no difference with -march=armv8.5-a
		OPTFLAGS =
	endif
endif

# PowerPC doesn't support -march=native
ifneq ($(filter ppc64%, $(shell uname -m)), )
	OPTFLAGS =
endif

# Add to PostgreSQL compile flags
PG_CFLAGS += $(OPTFLAGS) $(ARCH_FLAGS) -std=gnu11 -fno-lto \
             -Wno-unused-variable -Wno-unused-function

# Note: -fno-fat-lto-objects is added via CI environment variables for systems that support it

# Special flags for ObjectId compilation (MongoDB C driver needs C99+ features)
ifeq ($(MONGOC_AVAILABLE),yes)
  PG_CFLAGS += -Wno-declaration-after-statement
endif

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

# Special build rule for ObjectId (needs C99+ features for MongoDB C driver)
ifeq ($(MONGOC_AVAILABLE),yes)
src/objectid.o: src/objectid.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $(PG_CFLAGS) -Wno-declaration-after-statement -c $< -o $@
endif

# Use standard PostgreSQL testing
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
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
