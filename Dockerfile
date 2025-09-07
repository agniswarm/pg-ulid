# simple Dockerfile for building/installing C PostgreSQL extension (Ubuntu 22.04)
# Build example: docker build --build-arg POSTGRES_VERSION=16 -t ulid-pg:16 .

FROM ubuntu:24.04

# allow build-time override
ARG POSTGRES_VERSION=17
ENV POSTGRES_VERSION=${POSTGRES_VERSION}
ENV PG_LIB_DIR=/usr/lib/postgresql/${POSTGRES_VERSION}/lib
ENV PG_SHARE_DIR=/usr/share/postgresql/${POSTGRES_VERSION}/extension
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Add PostgreSQL repo
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends wget ca-certificates gnupg lsb-release; \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list; \
    wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -; \
    rm -rf /var/lib/apt/lists/*

# Install build + runtime dependencies
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      build-essential \
      git \
      pkg-config \
      libssl-dev \
      postgresql-server-dev-${POSTGRES_VERSION} \
      postgresql-${POSTGRES_VERSION} \
      postgresql-client-${POSTGRES_VERSION}; \
    rm -rf /var/lib/apt/lists/*

# make pg binaries available in PATH (so pg_config, initdb, etc are found)
ENV PATH=/usr/lib/postgresql/${POSTGRES_VERSION}/bin:$PATH

# build directory
WORKDIR /app

# copy source (adjust if your repo has different layout)
COPY . .

# build extension; try make install, fallback to manual copy if that fails
RUN set -eux; \
    make clean || true; \
    make || true; \
    # ensure extension dirs exist
    mkdir -p "${PG_LIB_DIR}" "${PG_SHARE_DIR}"; \
    if make install; then \
      echo "make install succeeded"; \
    else \
      echo "make install failed — doing manual install fallback"; \
      # copy likely artifact names; adapt if your outputs differ
      cp -v ./ulid.so "${PG_LIB_DIR}/" || true; \
      cp -v ./ulid.control "${PG_SHARE_DIR}/" || true; \
      cp -v ./sql/*.sql "${PG_SHARE_DIR}/" || true; \
    fi

# Optional: quick verification (list installed extension files)
RUN set -eux; \
    echo "Extension files in ${PG_LIB_DIR}:"; ls -la "${PG_LIB_DIR}" || true; \
    echo "Extension files in ${PG_SHARE_DIR}:"; ls -la "${PG_SHARE_DIR}" || true

# Set environment variables for testing
ENV PGDATA=/var/lib/postgresql/data
ENV PG_BIN_DIR=/usr/lib/postgresql/${POSTGRES_VERSION}/bin
ENV SKIP_INSTALLCHECK=0

# Run tests
RUN set -eux; \
    if [ "${SKIP_INSTALLCHECK}" != "1" ]; then \
      echo "Running make installcheck..."; \
      # create data dir
      rm -rf "${PGDATA}"; mkdir -p "${PGDATA}"; chown -R postgres:postgres "${PGDATA}"; chmod 700 "${PGDATA}"; \
      # initdb using chosen pg binaries
      su - postgres -s /bin/bash -c "${PG_BIN_DIR}/initdb -D '${PGDATA}' --encoding=UTF8" ; \
      # start cluster (listen only on unix socket in /tmp to avoid network binding issues)
      su - postgres -s /bin/bash -c "${PG_BIN_DIR}/pg_ctl -D '${PGDATA}' -o \"-c listen_addresses='' -c unix_socket_directories='/tmp'\" -w start"; \
      # create test DB
      su - postgres -s /bin/bash -c "PGHOST=/tmp ${PG_BIN_DIR}/createdb testdb"; \
      # Attempt to create extension (ignore errors but installcheck expects installed files)
      su - postgres -s /bin/bash -c "PGHOST=/tmp psql -d testdb -c \"CREATE EXTENSION IF NOT EXISTS ulid;\" || true"; \
      # run tests (this will exit non-zero if tests fail)
      echo "Executing make installcheck (this may fail if tests fail)"; \
      if su - postgres -s /bin/bash -c "cd /app && PGHOST=/tmp make installcheck"; then \
        echo "installcheck passed"; \
      else \
        echo "installcheck failed"; \
        # stop cluster and exit with non-zero so the build fails; comment next line if you prefer build to continue
        su - postgres -s /bin/bash -c "${PG_BIN_DIR}/pg_ctl -D '${PGDATA}' -m fast -w stop"; \
        exit 1; \
      fi; \
      # stop cluster and cleanup
      su - postgres -s /bin/bash -c "${PG_BIN_DIR}/pg_ctl -D '${PGDATA}' -m fast -w stop"; \
      rm -rf "${PGDATA}"; \
    else \
      echo "SKIP_INSTALLCHECK=1 — skipping installcheck"; \
    fi

# Expose postgres port (optional for runtime usage)
EXPOSE 5432

# Default: show postgres version (user can override CMD to run postgres or bash)
CMD ["postgres"]
