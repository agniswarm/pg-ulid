#
# Makefile.win - nmake (MSVC) build for the ulid extension
#
# Usage (Developer Command Prompt):
#   set PGROOT=C:\Program Files\PostgreSQL\17
#   nmake /F Makefile.win
#   nmake /F Makefile.win install
#   nmake /F Makefile.win installcheck
#   nmake /F Makefile.win clean
#

# ---------- Preconditions ----------
!IF "$(PGROOT)" == ""
!ERROR PGROOT environment variable is not set. Set PGROOT to your Postgres installation root.
!ENDIF

BINDIR    = $(PGROOT)\bin
INCLUDEDIR = $(PGROOT)\include
INCLUDEDIR_SERVER = $(PGROOT)\include\server
LIBDIR    = $(PGROOT)\lib
SHAREDIR  = $(PGROOT)\share
PKGLIBDIR = $(LIBDIR)

CC        = cl
LINKER    = link

EXTENSION = ulid
EXTVERSION = 0.1.1

SRCDIR    = src
OBJDIR    = src
SRC       = $(SRCDIR)\ulid.c
OBJ       = $(OBJDIR)\ulid.obj
SHLIB     = $(EXTENSION).dll
LIBS      = "$(LIBDIR)\postgres.lib"

# Compiler flags - tuned for release builds (adjust as needed)
CFLAGS    = /nologo /MD /O2 /I"$(INCLUDEDIR_SERVER)\port\win32_msvc" /I"$(INCLUDEDIR_SERVER)\port\win32" /I"$(INCLUDEDIR_SERVER)" /I"$(INCLUDEDIR)"

# Link flags
LFLAGS    = /nologo

# ---------- Default target ----------
all: $(SHLIB)

# Compile source to object
$(OBJ): $(SRC)
	@echo Compiling $(SRC) -> $(OBJ)
	$(CC) $(CFLAGS) /c $(SRC) /Fo$(OBJ)

# Link object into DLL
$(SHLIB): $(OBJ)
	@echo Linking $(SHLIB)
	$(LINKER) $(LFLAGS) /DLL /OUT:$(SHLIB) $(OBJ) $(LIBS)

# Install: copy DLL and SQL/control into PG lib and share dirs
install: all
	@echo Installing $(SHLIB) to $(PKGLIBDIR)
	copy /Y "$(SHLIB)" "$(PKGLIBDIR)" || (echo Failed to copy DLL & exit /b 1)
	@echo Installing extension control and SQL files to $(SHAREDIR)\extension
	if not exist "$(SHAREDIR)\extension" ( mkdir "$(SHAREDIR)\extension" )
	copy /Y "$(EXTENSION).control" "$(SHAREDIR)\extension" || (echo Failed to copy control file & exit /b 1)
	copy /Y sql\$(EXTENSION)--*.sql "$(SHAREDIR)\extension" || (echo Failed to copy SQL file(s) & exit /b 1)
	@echo Install complete.

#
# installcheck: run the repository CI batch script (test\build\ci.bat)
# - This is intentionally a wrapper that:
#   1) tells you what's going to run,
#   2) verifies the CI script exists,
#   3) executes it from the repo root.
#
installcheck:
	@echo Running installcheck: invoking test\build\ci.bat
	if not exist "test\build\ci.bat" ( \
		echo "ERROR: test\\build\\ci.bat not found in repository root" && exit /b 1 \
	)
	@echo "Executing test\\build\\ci.bat -- this may run postgres service and full test suite"
	call test\build\ci.bat

# Clean build artifacts
clean:
	-@if exist $(OBJ) del /F /Q $(OBJ)
	-@if exist $(SHLIB) del /F /Q $(SHLIB)
	-@if exist $(EXTENSION).lib del /F /Q $(EXTENSION).lib
	-@if exist $(EXTENSION).exp del /F /Q $(EXTENSION).exp
	@echo Cleaned.

# Uninstall: remove installed files (best-effort; needs appropriate permissions)
uninstall:
	-@if exist "$(PKGLIBDIR)\$(SHLIB)" del /F /Q "$(PKGLIBDIR)\$(SHLIB)"
	-@if exist "$(SHAREDIR)\extension\$(EXTENSION).control" del /F /Q "$(SHAREDIR)\extension\$(EXTENSION).control"
	-@for %%f in ("$(SHAREDIR)\extension\$(EXTENSION)--*.sql") do ( if exist "%%~f" del /F /Q "%%~f" )

.PHONY: all install installcheck clean uninstall
