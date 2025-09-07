# Makefile for ulid extension (C implementation) - cross-platform (Linux/macOS)

EXTENSION = ulid
VERSION ?= 0.1.1
DATA = sql/$(EXTENSION)--$(VERSION).sql

# PGXS module / object definitions
MODULES = $(EXTENSION)
OBJS = $(EXTENSION).o
PG_CONFIG ?= pg_config

# --- Safety checks for pg_config / pgxs ---

PG_CONFIG_PATH := $(shell which $(PG_CONFIG) 2>/dev/null || true)
ifeq ($(PG_CONFIG_PATH),)
$(error "pg_config not found in PATH. Ensure Postgres dev files are installed and pg_config is on PATH")
endif

PGXS := $(shell $(PG_CONFIG) --pgxs 2>/dev/null || true)
ifeq ($(PGXS),)
$(error "pg_config found but --pgxs did not return a value. Ensure Postgres dev files (pgxs) are available.")
endif

# --- Compiler/linker flags ---

# Avoid LTO to prevent macOS clang/LLVM bitcode issues
PG_CPPFLAGS += -fno-lto -fno-fat-lto-objects
PG_CFLAGS   += -fno-lto -fno-fat-lto-objects
PG_LDFLAGS  += -fno-lto -fno-fat-lto-objects

# --- Include PGXS makefile generator ---
# This provides targets: all, install, installcheck, clean, etc.
include $(PGXS)

# --- Explicit compile rules ---
# OBJS is "ulid.o", so we tell make how to build it from src/ulid.c
$(EXTENSION).o: src/$(EXTENSION).c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ $<

# Rule for building bitcode file (for PostgreSQL JIT compilation)
# Only build if we have the necessary tools
ifneq ($(CLANG),)
$(EXTENSION).bc: src/$(EXTENSION).c
	$(CLANG) $(BITCODE_CPPFLAGS) $(BITCODE_CFLAGS) -c -o $@ $<
endif

# --- Extra targets ---

# Install a helper binary if you ever add one (no-op by default)
install-binary:
	@echo "install-binary: no helper binary to install by default (add commands if needed)"

# Override clean to handle both locations
clean:
	rm -f $(EXTENSION).o $(EXTENSION).so $(EXTENSION).bc
	rm -f src/*.o src/*.so src/*.bc

.PHONY: install-binary clean
