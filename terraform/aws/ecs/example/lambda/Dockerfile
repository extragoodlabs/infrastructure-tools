FROM rust:1.62 as build
# ARG binary

RUN apt-get update
RUN cargo install cargo-lambda
WORKDIR /usr/local/bin
RUN wget -qO- https://ziglang.org/builds/zig-linux-x86_64-0.10.0-dev.3027+0e26c6149.tar.xz | tar -xJ --strip-components=1 zig-linux-x86_64-0.10.0-dev.3027+0e26c6149/zig zig-linux-x86_64-0.10.0-dev.3027+0e26c6149/lib

WORKDIR /usr/src/api
COPY Cargo.toml Cargo.toml
COPY src src
RUN cargo lambda build --release --workspace --arm64 --output-format=zip

FROM scratch as export
ARG name
COPY --from=build /usr/src/api/target/lambda/${name}/bootstrap.zip /${name}.zip
