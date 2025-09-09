# syntax=docker/dockerfile:1

ARG PG_MAJOR=17
ARG DEBIAN_CODENAME=bookworm
FROM postgres:$PG_MAJOR-$DEBIAN_CODENAME
ARG PG_MAJOR

# Copy source code
COPY . /tmp/ulid-extension

RUN apt-get update && \
		apt-mark hold locales && \
		apt-get install -y --no-install-recommends build-essential postgresql-server-dev-$PG_MAJOR libmongoc-dev libbson-dev libmongoc-1.0-0 libbson-1.0-0 && \
		cd /tmp/ulid-extension && \
		make clean && \
		make OPTFLAGS="" && \
		make install && \
		mkdir /usr/share/doc/ulid-extension && \
		cp LICENSE README.md /usr/share/doc/ulid-extension && \
		rm -r /tmp/ulid-extension && \
		apt-get remove -y build-essential postgresql-server-dev-$PG_MAJOR libmongoc-dev libbson-dev && \
		apt-get autoremove -y && \
		apt-mark unhold locales && \
		rm -rf /var/lib/apt/lists/*
