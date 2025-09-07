#
# Makefile - Unix (Linux / macOS) build for PostgreSQL ULID extension
#
# Usage:
#   make                 # build for native arch (usually x86_64)
#   make TARGET_ARCH=i386  # build 32-bit (if toolchain & postgres headers for i386 available)
#   make install
#   make installcheck
#   make clean
#   make uninstall
#
# Notes:
#  - Requires pg_config in PATH (installed with PostgreSQL dev files).
#  - If you want to link against an external ulid-c library, set:
#       ULID_C_DIR=/path/to/ulid-c
#    and adjust ULID_C_LIB accordingly (see below).
#

EXTENSION = ulid
EXTVERSION = 0.1.1

MODULE_big = $(EXTENSION)
OBJS = src/ulid.o
DATA = $(EXTENSION).control sql/$(EXTENSION)--$(EXTVERSION).sql

# Use pg_config to discover PGXS; fallback to pg_config in PATH
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs 2>/dev/null || true)
ifeq ($(PGXS),)
$(error "pg_config not found or PGXS not available. Install PostgreSQL dev packages or set PG_CONFIG")
endif

include $(PGXS)

# Optional: point to ulid-c include/lib if you want to use it
# e.g. make ULID_C_DIR=/usr/local
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

# Target architecture override (defaults to host)
# Example: make TARGET_ARCH=i386
TARGET_ARCH ?= $(shell uname -m)

# Convert TARGET_ARCH to compiler flags
ARCH_FLAGS :=
ifeq ($(TARGET_ARCH), i386)
  ARCH_FLAGS += -m32
endif

# Mac: if building on macOS and you need a particular SDK, you can export SDKROOT or set MACOS_SDK
# MACOS_SDK ?= /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
# ifdef MACOS_SDK
#   ARCH_FLAGS += -isysroot $(MACOS_SDK)
# endif

# Safety: do not force -march=native on cross-platform builds
OPTFLAGS ?= -O2

# Add portable flags (avoid LTO to reduce cross-platform headaches)
PG_CFLAGS += $(OPTFLAGS) $(ARCH_FLAGS) -fno-lto -fno-fat-lto-objects

# Ensure we use CC from pgxs unless overridden
CC ?= $(HOSTCC)

# compile object (override to ensure we use GCC/Clang semantics)
src/%.o: src/%.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $(PG_CFLAGS) $(ULID_C_INCDIR) -c $< -o $@

# Allow make to build as usual by delegating to PGXS rules
all: all-local

all-local: $(MODULE_big).so

# Link step: rely on PGXS variables; this keeps compatibility with extension build process
$(MODULE_big).so: $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) $(ULID_C_LIBDIR) $(ULID_C_LIBS) -o $@

install: all
	$(MAKE) -f $(PGXS) install

installcheck: all
	# run platform installcheck; delegate to pg_regress via PGXS
	$(MAKE) -f $(PGXS) installcheck

uninstall:
	$(MAKE) -f $(PGXS) uninstall || true

clean:
	rm -f src/*.o
	rm -f $(MODULE_big).so
	rm -f regression.diffs regression.out

.PHONY: all all-local install installcheck uninstall clean
