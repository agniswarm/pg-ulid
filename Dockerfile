# syntax=docker/dockerfile:1
ARG PG_MAJOR=17
ARG DEBIAN_CODENAME=bookworm
FROM postgres:${PG_MAJOR}-${DEBIAN_CODENAME} AS builder

ARG PG_MAJOR

# Install build dependencies (including libmongoc if you want ObjectId support)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      pkg-config \
      postgresql-server-dev-${PG_MAJOR} \
      libbson-dev \
      libmongoc-dev \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/* \
      && rm -rf /tmp/* \
      && rm -rf /var/tmp/*

# Copy repository into the builder image
WORKDIR /tmp/ulid-extension
COPY . /tmp/ulid-extension

# Build and install extension into the Postgres directories
RUN set -eux; \
    cd /tmp/ulid-extension; \
    make clean && \
    make all && \
    make install

# Create a minimal runtime image by copying the installed extension files into a fresh Postgres image
FROM postgres:${PG_MAJOR}-${DEBIAN_CODENAME}

ARG PG_MAJOR

# Install runtime dependencies needed by the extension (.so)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
		libbson-1.0-0 \
		libmongoc-1.0-0 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

# Copy the installed extension files from the builder stage
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/ /usr/lib/postgresql/${PG_MAJOR}/lib/
COPY --from=builder /usr/share/postgresql/${PG_MAJOR}/extension/ /usr/share/postgresql/${PG_MAJOR}/extension/

# Optional: copy docs
COPY --from=builder /tmp/ulid-extension/README.md /usr/share/doc/ulid-extension/README.md
COPY --from=builder /tmp/ulid-extension/LICENSE /usr/share/doc/ulid-extension/LICENSE

# Ensure permissions are sane (postgres user owns files)
RUN chown -R postgres:postgres /usr/lib/postgresql/${PG_MAJOR}/lib/ \
    /usr/share/postgresql/${PG_MAJOR}/extension/ \
    /usr/share/doc/ulid-extension || true

# Add production metadata
LABEL maintainer="ULID Extension Team" \
      version="0.3.0" \
      description="PostgreSQL extension for ULID and ObjectId generation" \
      org.opencontainers.image.title="ulid-extension" \
      org.opencontainers.image.description="PostgreSQL extension providing ULID and MongoDB ObjectId support" \
      org.opencontainers.image.version="0.3.0" \
      org.opencontainers.image.source="https://github.com/your-org/ulid-extension" \
      org.opencontainers.image.licenses="MIT"

# Add health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pg_isready -U postgres || exit 1

# Security: Run as non-root user
USER postgres

EXPOSE 5432

# Use the default postgres entrypoint/cmd
