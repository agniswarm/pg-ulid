# syntax=docker/dockerfile:1

ARG PG_MAJOR=17
ARG DEBIAN_CODENAME=bookworm
FROM postgres:$PG_MAJOR-$DEBIAN_CODENAME
ARG PG_MAJOR

# Copy the ULID extension source code
COPY . /tmp/ulid-extension

RUN apt-get update && \
		apt-mark hold locales && \
		apt-get install -y --no-install-recommends build-essential postgresql-server-dev-$PG_MAJOR && \
		cd /tmp/ulid-extension && \
		make clean && \
		make OPTFLAGS="" && \
		make install && \
		ls -la /usr/share/postgresql/$PG_MAJOR/extension/ulid* && \
		mkdir -p /usr/share/doc/ulid-extension && \
		cp README.md /usr/share/doc/ulid-extension/ 2>/dev/null || true && \
		rm -rf /tmp/ulid-extension && \
		apt-get remove -y build-essential postgresql-server-dev-$PG_MAJOR && \
		apt-get autoremove -y && \
		apt-mark unhold locales && \
		rm -rf /var/lib/apt/lists/*
