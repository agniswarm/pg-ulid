# Makefile.win - nmake-compatible build for PostgreSQL ULID extension
#
# Usage:
#   - Preferred: export PGXS to the full path of pgxs.mk (e.g. via pg_config --pgxs)
#     then run: nmake /NOLOGO /F Makefile.win installcheck
#
#   - Fallback: if PGXS is not provided, export the following env vars (pg_setup.sh should do this):
#       PG_CONFIG       (full path to pg_config.exe or 'pg_config' on PATH)
#       PG_INCLUDEDIR   (Postgres include directory)
#       PG_LIBDIR       (Postgres lib directory)
#       PG_PKGLIBDIR    (Postgres pkglibdir - where extensions live)
#       PG_BINDIR       (Postgres bin dir)
#     Then run nmake. The Makefile will compile and link using cl/link by default.
#
#   - To use gcc/mingw instead of cl/link, set CC=gcc in the environment and adjust LINK_CMD accordingly.
#
# Note:
#   - This file uses only nmake-compatible syntax. Do not include $(shell ...) or GNU make conditionals here.

EXTENSION = ulid
EXTVERSION = 0.1.1

MODULE_big = $(EXTENSION)
OBJS = src\ulid.obj
DATA = $(EXTENSION).control sql\$(EXTENSION)--$(EXTVERSION).sql
REGRESS =

# default compiler: cl (MSVC). Override by setting CC in env (e.g. CC=gcc).
!IFNDEF CC
CC = cl
!ENDIF

# If PGXS is provided (preferred), include it. PGXS must be full path to pgxs.mk.
!IF "$(PGXS)" != ""
  !INCLUDE $(PGXS)
!ELSE

  # Fallback variables: try to read them from environment (set by pg_setup.sh)
  !IFDEF PG_INCLUDEDIR
    PG_INCLUDEDIR = $(PG_INCLUDEDIR)
  !ELSE
    PG_INCLUDEDIR =
  !ENDIF

  !IFDEF PG_LIBDIR
    PG_LIBDIR = $(PG_LIBDIR)
  !ELSE
    PG_LIBDIR =
  !ENDIF

  !IFDEF PG_PKGLIBDIR
    PG_PKGLIBDIR = $(PG_PKGLIBDIR)
  !ELSE
    PG_PKGLIBDIR =
  !ENDIF

  !IFDEF PG_BINDIR
    PG_BINDIR = $(PG_BINDIR)
  !ELSE
    PG_BINDIR =
  !ENDIF

  # Compiler / linker flags for MSVC (cl + link)
  # If you use gcc, set CC=gcc and override the compile/link commands below.
  ifdef CC
    # If CC == cl (MSVC) use MSVC flags; otherwise GCC flags are set below in compile/link commands.
  endif

  # Preprocessor include flags (MSVC style)
  PG_CFLAGS = /I"$(PG_INCLUDEDIR)"

  # Linker library path (MSVC)
  PG_LDFLAGS = /LIBPATH:"$(PG_LIBDIR)"

  # Link libraries - default link against libpq (MSVC import lib name)
  PG_LIBS = libpq.lib

  # Link command (MSVC). If you're using gcc, the Makefile will use an alternate link command.
  LINK_CMD_MSVC = link /DLL /OUT:$(EXTENSION).dll $(OBJS) $(PG_LDFLAGS) $(PG_LIBS)

!ENDIF

# Default compile rule - uses cl by default, or gcc if CC=gcc set in env.
src\ulid.obj: src\ulid.c
	@echo Building $<
	@if "$(CC)" == "cl" ( \
	  $(CC) $(CFLAGS) $(CPPFLAGS) $(PG_CFLAGS) /c src\ulid.c /Fo:src\ulid.obj \
	) else ( \
	  echo "Using gcc to compile"; \
	  $(CC) $(CFLAGS) $(CPPFLAGS) -I"$(PG_INCLUDEDIR)" -c src/ulid.c -o src/ulid.obj \
	)

# 'all' target. If PGXS included its own install/link rules, they usually provide a submake.
# When included, those rules will override; when not, we perform manual link here.
all: $(OBJS)
	@echo Objects built.
	!IF "$(PGXS)" == ""
		@echo PGXS not available; performing manual link for extension...
		@if "$(CC)" == "cl" ( \
		  $(LINK_CMD_MSVC) \
		) else ( \
		  echo "Linking with gcc (mingw)"; \
		  $(CC) -shared -o $(EXTENSION).dll $(OBJS) -L"$(PG_LIBDIR)" -lpq \
		) \
	!ENDIF

# install target: if PGXS included, its install target will typically be available; fallback copies .dll to pkglibdir
install: all
	@echo Installing extension...
	!IF "$(PGXS)" != ""
		@echo Using PGXS rules for install (if available)...
		@rem If pgxs provided install target this will invoke it
	!ELSE
		@if exist "$(PG_PKGLIBDIR)" ( \
		  copy /Y "$(EXTENSION).dll" "$(PG_PKGLIBDIR)\" > nul && echo "Copied $(EXTENSION).dll to $(PG_PKGLIBDIR)" \
		) else ( \
		  echo "PG_PKGLIBDIR not set or does not exist; cannot copy extension. Please set PG_PKGLIBDIR to your Postgres pkglibdir." && exit 1 \
		) \
	!ENDIF

# installcheck: run Windows CI batch test script (test\build\ci.bat)
installcheck: install
	@echo Running Windows CI batch test script...
	cmd.exe /C "cd /d %CD% && test\build\ci.bat"

# uninstall target: best-effort remove files from pkglibdir
uninstall:
	@echo Uninstalling extension (best-effort)...
	@if exist "$(PG_PKGLIBDIR)\$(EXTENSION).dll" ( \
	  del /Q "$(PG_PKGLIBDIR)\$(EXTENSION).dll" > nul && echo "Removed $(PG_PKGLIBDIR)\$(EXTENSION).dll" \
	) else ( \
	  echo "No installed $(EXTENSION).dll found in $(PG_PKGLIBDIR)" \
	) 

# Clean artifacts
clean:
	-@echo Cleaning artifacts...
	-@if exist src\ulid.obj del /Q src\ulid.obj 2>nul
	-@if exist $(EXTENSION).dll del /Q $(EXTENSION).dll 2>nul
	-@if exist results rmdir /S /Q results 2>nul
	-@if exist tmp_check rmdir /S /Q tmp_check 2>nul
	-@if exist regression.diffs del /Q regression.diffs 2>nul
	-@if exist regression.out del /Q regression.out 2>nul

# Show status helpful targets
help:
	@echo "Makefile.win targets:"
	@echo "  all         - build objects (and link if PGXS not available)"
	@echo "  install     - install extension (copies DLL to PG_PKGLIBDIR if PGXS not available)"
	@echo "  installcheck- run tests via test\\build\\ci.bat (after install)"
	@echo "  clean       - clean build artifacts"

# End of Makefile.win
