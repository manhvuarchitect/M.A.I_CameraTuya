ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest
FROM golang:1.23-alpine AS builder

RUN apk add --no-cache git gcc musl-dev

WORKDIR /build
COPY tuya-ipc-terminal /build
RUN go mod download \
    && CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o tuya-ipc-terminal .

# ─── Runtime image ────────────────────────────────────────────────────────────
FROM $BUILD_FROM

RUN apk add --no-cache \
    bash \
    tzdata \
    ca-certificates \
    ffmpeg \
    jq \
    expect

COPY --from=builder /build/tuya-ipc-terminal /usr/bin/tuya-ipc-terminal
RUN chmod +x /usr/bin/tuya-ipc-terminal

COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
