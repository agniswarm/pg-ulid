EXTENSION = ulid
EXTVERSION = 0.1.1

MODULE_big = ulid
DATA = $(wildcard sql/*--*--*.sql)
DATA_built = sql/$(EXTENSION)--$(EXTVERSION).sql
OBJS = src/ulid.o

TESTS = $(wildcard test/sql/*.sql)
REGRESS = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --load-extension=$(EXTENSION)

# To compile for portability, run: make OPTFLAGS=""
OPTFLAGS = -march=native

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

# For auto-vectorization:
# - GCC (needs -ftree-vectorize OR -O3) - https://gcc.gnu.org/projects/tree-ssa/vectorization.html
# - Clang (could use pragma instead) - https://llvm.org/docs/Vectorizers.html
PG_CFLAGS += $(OPTFLAGS) -ftree-vectorize -fassociative-math -fno-signed-zeros -fno-trapping-math

# Debug GCC auto-vectorization
# PG_CFLAGS += -fopt-info-vec

# Debug Clang auto-vectorization
# PG_CFLAGS += -Rpass=loop-vectorize -Rpass-analysis=loop-vectorize

# The SQL file already exists, no need to build it

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)

# Disable bitcode generation to avoid LLVM version conflicts
# Force regular object file compilation instead of bitcode
PG_CPPFLAGS += -fno-lto -fno-fat-lto-objects
PG_CFLAGS += -fno-lto -fno-fat-lto-objects
PG_LDFLAGS += -fno-lto -fno-fat-lto-objects

# Override compilation to force regular object files
CC = gcc

# Force disable LTO at the makefile level
override CFLAGS += -fno-lto -fno-fat-lto-objects
override LDFLAGS += -fno-lto -fno-fat-lto-objects

include $(PGXS)

# Override the object file compilation to ensure regular .o files
src/ulid.o: src/ulid.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

# Create version-specific SQL file for PostgreSQL 19+ compatibility
sql/ulid--19devel.sql: sql/ulid--0.1.1.sql
	cp $< $@

# Clean targets
clean:
	rm -f src/*.o
	rm -f src/*.bc
	rm -f $(MODULE_big).so
	rm -f $(MODULE_big).dll
	rm -f $(MODULE_big).dylib
	rm -f regression.diffs
	rm -f regression.out
	rm -f sql/ulid--19devel.sql

# for Mac
ifeq ($(PROVE),)
	PROVE = prove
endif

# for Postgres < 15
# PROVE_FLAGS += -I ./test/perl

# Installcheck target - run comprehensive tests
installcheck: all
	@echo "Running comprehensive extension tests..."
	@if [ -f "test/build/ci.sh" ]; then \
		echo "Starting PostgreSQL service..."; \
		/etc/init.d/postgresql start || service postgresql start || true; \
		sleep 3; \
		echo "Running test suite..."; \
		bash test/build/ci.sh; \
		echo "✅ All tests completed successfully"; \
	else \
		echo "ERROR: test/build/ci.sh not found"; \
		echo "Available test files:"; \
		ls -la test/ || echo "No test directory found"; \
		exit 1; \
	fi

# Test specific PostgreSQL version using Docker
test-docker:
	@echo "Testing with Docker builds..."
	@echo "Available PostgreSQL versions:"
	@echo "  make test-pg14  - Test PostgreSQL 14 (Ubuntu 22.04)"
	@echo "  make test-pg16  - Test PostgreSQL 16 (Ubuntu 24.04)"
	@echo "  make test-pg17  - Test PostgreSQL 17 (Ubuntu 22.04)"

test-pg14:
	@echo "Testing PostgreSQL 14 on Ubuntu 22.04..."
	docker build --build-arg POSTGRES_VERSION=14 -t ulid-pg:14 .

test-pg16:
	@echo "Testing PostgreSQL 16 on Ubuntu 24.04..."
	docker build --build-arg POSTGRES_VERSION=16 -t ulid-pg:16 .

test-pg17:
	@echo "Testing PostgreSQL 17 on Ubuntu 22.04..."
	docker build --build-arg POSTGRES_VERSION=17 -t ulid-pg:17 .

# Help target
help:
	@echo "Available targets:"
	@echo "  all              - Build the extension (default)"
	@echo "  install          - Install the extension"
	@echo "  installcheck     - Run comprehensive extension tests"
	@echo "  clean            - Clean build artifacts"
	@echo "  test-docker      - Show Docker testing options"
	@echo "  test-pg14        - Test PostgreSQL 14 with Docker"
	@echo "  test-pg16        - Test PostgreSQL 16 with Docker"
	@echo "  test-pg17        - Test PostgreSQL 17 with Docker"
	@echo "  help             - Show this help message"

.PHONY: all install installcheck clean test-docker test-pg14 test-pg16 test-pg17 help
