# DeskAgent Control Plane — Linux container build (cho Docker/VPS).
# Standalone crate (riêng lockfile). --locked: build đúng rev đã gate local;
# (không --offline: image rust:slim chưa có registry cache, nhưng lockfile
# pin toàn bộ version nên không trôi dependency).
# Build:  docker build -t deskagent-control-plane .
FROM rust:1.75-slim AS build
WORKDIR /src
COPY . .
RUN cargo build --release --locked

FROM debian:bookworm-slim
COPY --from=build /src/target/release/deskagent-control-plane /usr/local/bin/
EXPOSE 34116 34117 34118
ENTRYPOINT ["deskagent-control-plane"]
