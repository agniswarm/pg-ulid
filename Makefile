EXTENSION = ulid
EXTVERSION = 0.1.1

MODULE_big = ulid
DATA_built = sql/$(EXTENSION)--$(EXTVERSION).sql
OBJS = src/ulid.o

TESTS = $(wildcard test/sql/*.sql)
REGRESS = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --load-extension=$(EXTENSION)

# If no tests directory exists, use basic tests
ifeq ($(TESTS),)
	REGRESS = ulid_basic
	REGRESS_OPTS = --load-extension=$(EXTENSION)
endif

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Build the main SQL file from template if needed
sql/$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION)--$(EXTVERSION).sql
	@# File already exists, no need to copy

# For Mac
ifeq ($(PROVE),)
	PROVE = prove
endif

# For Postgres < 15
PROVE_FLAGS += -I ./test/perl

prove_installcheck:
	rm -rf $(CURDIR)/tmp_check
	cd $(srcdir) && TESTDIR='$(CURDIR)' PATH="$(bindir):$$PATH" PGPORT='6$(DEF_PGPORT)' PG_REGRESS='$(top_builddir)/src/test/regress/pg_regress' $(PROVE) $(PG_PROVE_FLAGS) $(PROVE_FLAGS) $(if $(PROVE_TESTS),$(PROVE_TESTS),test/t/*.pl)

# Basic test fallback if no test directory
test/sql/ulid_basic.sql:
	@mkdir -p test/sql test/expected
	@echo "-- Basic ULID extension test" > test/sql/ulid_basic.sql
	@echo "CREATE EXTENSION ulid;" >> test/sql/ulid_basic.sql
	@echo "SELECT ulid() IS NOT NULL AS ulid_generated;" >> test/sql/ulid_basic.sql
	@echo "SELECT ulid_random() IS NOT NULL AS ulid_random_generated;" >> test/sql/ulid_basic.sql
	@echo "DROP EXTENSION ulid;" >> test/sql/ulid_basic.sql
	@echo "-- Basic ULID extension test" > test/expected/ulid_basic.out
	@echo "CREATE EXTENSION ulid;" >> test/expected/ulid_basic.out
	@echo "SELECT ulid() IS NOT NULL AS ulid_generated;" >> test/expected/ulid_basic.out
	@echo " ulid_generated " >> test/expected/ulid_basic.out
	@echo "----------------" >> test/expected/ulid_basic.out
	@echo " t" >> test/expected/ulid_basic.out
	@echo "(1 row)" >> test/expected/ulid_basic.out
	@echo "" >> test/expected/ulid_basic.out
	@echo "SELECT ulid_random() IS NOT NULL AS ulid_random_generated;" >> test/expected/ulid_basic.out
	@echo " ulid_random_generated " >> test/expected/ulid_basic.out
	@echo "-----------------------" >> test/expected/ulid_basic.out
	@echo " t" >> test/expected/ulid_basic.out
	@echo "(1 row)" >> test/expected/ulid_basic.out
	@echo "" >> test/expected/ulid_basic.out
	@echo "DROP EXTENSION ulid;" >> test/expected/ulid_basic.out

# Ensure test files exist before running installcheck
installcheck: test/sql/ulid_basic.sql
