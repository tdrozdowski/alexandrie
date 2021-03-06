#
# Dockerfile for the Alexandrie crate registry application
#
# The output docker image will assume the default Cargo.toml options
# (i.e., sqlite3 database)
#

### First stage: build the application
FROM rust:1.40-slim-buster as builder

ARG DATABASE

RUN apt update
RUN apt install -y clang
# install proper dependencies for each database
# for postgresql and mysql, install diesel as well to set up the database
# for sqlite make a dummy file for Docker to copy
RUN \
    if [ "${DATABASE}" = "sqlite" ]; then \
        apt install -y sqlite3 libsqlite3-dev; \
        mkdir -p /usr/local/cargo/bin/; \
        touch /usr/local/cargo/bin/diesel; \
    fi && \
    if [ "${DATABASE}" = "postgresql" ]; then \
        apt install -y  libpq-dev; \
        cargo install diesel_cli --no-default-features --features "postgres"; \
    fi && \
    if [ "${DATABASE}" = "mysql" ]; then \
        apt install -y default-libmysqlclient-dev; \
        cargo install diesel_cli --no-default-features --features "mysql"; \
    fi

WORKDIR /alexandrie

# copy source data
COPY src src
COPY syntect-syntaxes syntect-syntaxes
COPY syntect-themes syntect-themes
COPY migrations migrations
COPY wasm-pbkdf2 wasm-pbkdf2
COPY docker/$DATABASE/Cargo.toml Cargo.toml
COPY Cargo.lock Cargo.lock

# build the app
RUN cargo build --release


### Second stage: copy built application
FROM debian:buster-slim as runner

ARG DATABASE

# install run dependencies, then clean up apt cache
RUN apt update && \
    apt install -y openssh-client git && \
    if [ "${DATABASE}" = "sqlite" ]; then apt install -y sqlite3; fi && \
    if [ "${DATABASE}" = "postgresql" ]; then apt install -y  postgresql; fi && \
    if [ "${DATABASE}" = "mysql" ]; then apt install -y default-mysql-server default-mysql-client; fi && \
    apt-get clean && rm -rf /var/lib/apt/lists/


# copy run files
COPY --from=builder /alexandrie/target/release/alexandrie /usr/bin/alexandrie
# copy docker_cli
COPY --from=builder /usr/local/cargo/bin/diesel /usr/bin/diesel
# add the startup file
COPY docker/startup.sh /home/alex/startup.sh
# copy runtime assets
COPY assets /home/alex/assets
COPY syntect-dumps /home/alex/syntect-dumps
COPY templates /home/alex/templates
COPY migrations /home/alex/migrations
# copy diesel config
COPY diesel.toml /home/alex/diesel.toml


# combine run instructions to reduce docker layers & overall image size
RUN \
    # make a non-root user
    groupadd -g 1000 alex && \
    useradd -u 1000 -g 1000 alex && \
    # make the user directory & give them access to everything in it
    # mkdir -p /home/alex && \
    mkdir -p /home/alex/.ssh && \
    chown -R alex:alex /home/alex && \
    # give alex ownership of diesel
    chown alex:alex /usr/bin/diesel && \
    # give alex ownership of the startup script & make it executable
    chmod +x /home/alex/startup.sh


# switch to the non-root user to run the main process
USER alex
WORKDIR /home/alex


# make sure github is in the list of known hosts
# we'll do this at build time, rather than every run time
RUN ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

CMD ./startup.sh
