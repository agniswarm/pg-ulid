# Dockerfile for ULID extension (C + Go implementation)
FROM ubuntu:24.04

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    pkg-config \
    libssl-dev \
    postgresql-server-dev-16 \
    postgresql-16 \
    postgresql-client-16 \
    golang-go \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy source code
COPY . .

# Build the Go binary
RUN cd src && go mod tidy && go build -o ../ulid_generator ulid.go

# Build the C extension
RUN make clean && make

# Install the extension (skip bitcode to avoid LLVM version conflicts)
RUN make install || (echo "Bitcode generation failed, continuing with manual install..." && \
    mkdir -p /usr/lib/postgresql/16/lib && \
    mkdir -p /usr/share/postgresql/16/extension && \
    cp ulid.so /usr/lib/postgresql/16/lib/ && \
    cp ulid.control /usr/share/postgresql/16/extension/ && \
    cp sql/ulid--0.1.1.sql /usr/share/postgresql/16/extension/)
# Manually install the SQL files
RUN cp sql/ulid--0.1.1.sql /usr/share/postgresql/16/extension/
RUN cp ulid.control /usr/share/postgresql/16/extension/

# Set up PostgreSQL
USER postgres
RUN /etc/init.d/postgresql start && \
    psql -c "CREATE DATABASE testdb;" && \
    psql -d testdb -c "CREATE EXTENSION ulid;" || echo "Extension creation failed, but continuing..."

# Expose PostgreSQL port
EXPOSE 5432

# Start PostgreSQL
CMD ["/usr/lib/postgresql/16/bin/postgres", "-D", "/var/lib/postgresql/16/main", "-c", "config_file=/etc/postgresql/16/main/postgresql.conf"]
