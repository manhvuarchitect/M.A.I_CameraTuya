ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest
FROM golang:1.23-alpine AS builder

RUN apk add --no-cache git gcc musl-dev

WORKDIR /build
RUN git clone https://github.com/seydx/tuya-ipc-terminal.git . \
    && go mod download \
    && CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o tuya-ipc-terminal .

# ─── Runtime image ────────────────────────────────────────────────────────────
FROM $BUILD_FROM

# Install runtime deps
RUN apk add --no-cache \
    bash \
    tzdata \
    ca-certificates \
    ffmpeg \
    jq

# Copy binary from builder
COPY --from=builder /build/tuya-ipc-terminal /usr/bin/tuya-ipc-terminal
RUN chmod +x /usr/bin/tuya-ipc-terminal

# Run script
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
