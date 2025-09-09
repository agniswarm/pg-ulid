# syntax=docker/dockerfile:1

ARG PG_MAJOR=17
ARG DEBIAN_CODENAME=bookworm
FROM postgres:$PG_MAJOR-$DEBIAN_CODENAME
ARG PG_MAJOR

# Copy the ULID extension source code
COPY . /tmp/ulid-extension

RUN apt-get update && \
		apt-mark hold locales && \
		apt-get install -y --no-install-recommends build-essential postgresql-server-dev-$PG_MAJOR pkg-config && \
		apt-get install -y --no-install-recommends libmongoc-dev libbson-dev && \
		cd /tmp/ulid-extension && \
		echo "=== Starting build process ===" && \
		make clean && \
		echo "=== Running make ===" && \
		make all OPTFLAGS="" && \
		echo "=== Skipping installcheck ===" && \
		echo "=== Running make install ===" && \
		cp ulid.so /usr/lib/postgresql/$PG_MAJOR/lib/ && \
		cp ulid.control /usr/share/postgresql/$PG_MAJOR/extension/ && \
		sed "s|MODULE_PATHNAME|/usr/lib/postgresql/$PG_MAJOR/lib/ulid|g" sql/ulid--0.2.0.sql > /usr/share/postgresql/$PG_MAJOR/extension/ulid--0.2.0.sql && \
		echo "=== Checking installed files ===" && \
		ls -la /usr/share/postgresql/$PG_MAJOR/extension/ulid* && \
		ls -la /usr/lib/postgresql/$PG_MAJOR/lib/ulid* && \
		mkdir -p /usr/share/doc/ulid-extension && \
		cp README.md /usr/share/doc/ulid-extension/ 2>/dev/null || true && \
		rm -rf /tmp/ulid-extension && \
		apt-get remove -y build-essential postgresql-server-dev-$PG_MAJOR && \
		apt-get autoremove -y && \
		apt-mark unhold locales && \
		rm -rf /var/lib/apt/lists/*
