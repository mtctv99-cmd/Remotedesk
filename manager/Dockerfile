# DeskAgent Manager — Linux container build (cho Docker/VPS).
# Console admin đã được nhúng vào binary qua include_str! — không cần copy thêm file nào.
# Build:  docker build -t deskagent-manager .
# Run:    docker run -d -p 8080:8080 -v manager-data:/data -w /data deskagent-manager
FROM rust:1.75-slim AS build
WORKDIR /src
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
COPY --from=build /src/target/release/deskagent-manager /usr/local/bin/
EXPOSE 8080
ENTRYPOINT ["deskagent-manager"]
