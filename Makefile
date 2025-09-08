#
# Makefile - Unix (Linux / macOS) build for PostgreSQL ULID extension
#

EXTENSION = ulid
EXTVERSION = 0.1.1

MODULE_big = $(EXTENSION)
OBJS = src/ulid.o
DATA = $(EXTENSION).control sql/$(EXTENSION)--$(EXTVERSION).sql
REGRESS =

# Use pg_config to discover PGXS; fallback to pg_config in PATH
PG_CONFIG ?= pg_config
# Explicitly get the path to PGXS using pg_config, and fail with a clear error if not found.
PG_CONFIG_PATH := $(shell which $(PG_CONFIG) 2>/dev/null)
ifeq ($(PG_CONFIG_PATH),)
$(error "pg_config not found in PATH. Please install PostgreSQL development packages or set PG_CONFIG. PATH: $(PATH)")
endif

PGXS := $(shell $(PG_CONFIG) --pgxs 2>/dev/null)
ifeq ($(PGXS),)
$(error "PGXS not available from pg_config ($(PG_CONFIG)). Please ensure PostgreSQL development files are installed. PG_CONFIG: $(PG_CONFIG_PATH)")
endif

include $(PGXS)

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

TARGET_ARCH ?= $(shell uname -m)
ARCH_FLAGS :=
ifeq ($(TARGET_ARCH), i386)
  ARCH_FLAGS += -m32
endif

OPTFLAGS ?= -O2

PG_CFLAGS += $(OPTFLAGS) $(ARCH_FLAGS) -std=gnu11 -fno-lto -fno-fat-lto-objects \
             -Wno-unused-variable -Wno-unused-function

CC ?= $(HOSTCC)

src/%.o: src/%.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $(PG_CFLAGS) $(ULID_C_INCDIR) -c $< -o $@

# Custom installcheck: run our own CI script
installcheck: all
	@echo "Running extension tests via test/build/ci.sh..."
	@if [ -f "test/build/ci.sh" ]; then \
		bash test/build/ci.sh; \
	else \
		echo "ERROR: test/build/ci.sh not found"; \
		exit 1; \
	fi

.PHONY: all all-local install installcheck uninstall clean
