#
# Makefile - PostgreSQL ULID extension with optional ObjectId support
# Based on pgvector's build system with conditional MongoDB support
#

EXTENSION = ulid
EXTVERSION = 0.2.0

MODULE_big = $(EXTENSION)
OBJS = src/ulid.o
DATA = $(EXTENSION).control sql/$(EXTENSION)--$(EXTVERSION).sql
HEADERS = src/ulid.h

TESTS = $(wildcard test/sql/*.sql)
REGRESS = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --inputdir=test --load-extension=$(EXTENSION)

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
  DATA += sql/objectid--$(EXTVERSION).sql
  HEADERS += src/objectid.h
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

# Use standard PostgreSQL testing
# installcheck target is provided by PGXS

.PHONY: all all-local install installcheck uninstall clean

# include PGXS at the end so variables above are used by PGXS rules
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
