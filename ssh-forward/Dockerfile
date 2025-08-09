# syntax=docker/dockerfile:1

## Build stage
FROM --platform=$BUILDPLATFORM golang:1.22 as builder
WORKDIR /src

# Cache deps
COPY ssh-forward/go.mod ./go.mod
RUN go mod download

COPY ssh-forward/ ./

# Build static binary for linux/amd64 by default (overridden by buildx)
ENV CGO_ENABLED=0
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    go build -trimpath -ldflags='-s -w' -o /out/ssh-forwarder ./

## Runtime stage
FROM scratch
COPY --from=builder /out/ssh-forwarder /ssh-forwarder
EXPOSE 7022
ENTRYPOINT ["/ssh-forwarder"]

