# syntax=docker/dockerfile:1

ARG PG_MAJOR=17
ARG DEBIAN_CODENAME=bookworm
FROM postgres:$PG_MAJOR-$DEBIAN_CODENAME
ARG PG_MAJOR

# Copy the current directory (build context) to the container
COPY . /tmp/pg-ulid

RUN apt-get update && \
		apt-mark hold locales && \
		apt-get install -y --no-install-recommends build-essential postgresql-server-dev-$PG_MAJOR ca-certificates wget git && \
		cd /tmp/pg-ulid && \
		# Install Go 1.21 based on architecture
		ARCH=$(dpkg --print-architecture) && \
		if [ "$ARCH" = "arm64" ]; then \
			wget -O go1.21.6.linux-arm64.tar.gz https://go.dev/dl/go1.21.6.linux-arm64.tar.gz && \
			tar -C /usr/local -xzf go1.21.6.linux-arm64.tar.gz && \
			rm go1.21.6.linux-arm64.tar.gz; \
		else \
			wget -O go1.21.6.linux-amd64.tar.gz https://go.dev/dl/go1.21.6.linux-amd64.tar.gz && \
			tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz && \
			rm go1.21.6.linux-amd64.tar.gz; \
		fi && \
		export PATH=$PATH:/usr/local/go/bin && \
		export GOPROXY=direct && \
		export GOSUMDB=off && \
		make clean && \
		make OPTFLAGS="" && \
		make install && \
		mkdir /usr/share/doc/pg-ulid && \
		cp LICENSE README.md /usr/share/doc/pg-ulid && \
		rm -r /tmp/pg-ulid && \
		apt-get remove -y build-essential postgresql-server-dev-$PG_MAJOR ca-certificates wget git && \
		apt-get autoremove -y && \
		apt-mark unhold locales && \
		rm -rf /var/lib/apt/lists/*
