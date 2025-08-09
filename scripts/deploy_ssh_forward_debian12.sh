#!/usr/bin/env bash
set -euo pipefail

# One-click deploy script for Debian 12 (ssh-forward, uses Docker)
# - Installs Docker if missing
# - Pulls published image by default
# - Set BUILD_LOCAL=1 to build locally with docker buildx
# - Override registry via IMAGE_REGISTRY or full IMAGE

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Defaults
DEFAULT_REMOTE_IMAGE="ghcr.io/andjohnsonj5/github-ssh-forwarder:main"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-}"
BUILD_LOCAL="${BUILD_LOCAL:-0}"

IMAGE_DEFAULT="ssh-forward:local"
CONTAINER_NAME_DEFAULT="gh-ssh-forward"
HOST_PORT_DEFAULT=7022
CONTAINER_PORT_DEFAULT=7022

# Optional env passthrough to container
LISTEN_ADDR="${LISTEN_ADDR:-}"
UPSTREAM_ADDR="${UPSTREAM_ADDR:-}"
DIAL_TIMEOUT="${DIAL_TIMEOUT:-}"
IDLE_TIMEOUT="${IDLE_TIMEOUT:-}"
TCP_KEEPALIVE="${TCP_KEEPALIVE:-}"
MAX_CONNS="${MAX_CONNS:-}"

IMAGE="${IMAGE:-}"
CONTAINER_NAME="${CONTAINER_NAME:-$CONTAINER_NAME_DEFAULT}"
HOST_PORT="${HOST_PORT:-$HOST_PORT_DEFAULT}"
CONTAINER_PORT="${CONTAINER_PORT:-$CONTAINER_PORT_DEFAULT}"

info(){ echo -e "[INFO] $*"; }
err(){ echo -e "[ERROR] $*" >&2; }

ensure_root() {
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO=sudo
    else
      err "This script must be run as root or with sudo."; exit 1
    fi
  else
    SUDO=""
  fi
}

check_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "${ID:-}" != "debian" ] || [ "${VERSION_ID:-}" != "12" ]; then
      echo "Warning: target is Debian 12; detected ${ID:-} ${VERSION_ID:-}. Proceeding anyway."
    fi
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    info "Docker already installed"; return
  fi
  info "Installing Docker (official repository)"
  $SUDO apt-get update -y
  $SUDO apt-get install -y ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/debian/gpg | $SUDO gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
  $SUDO apt-get update -y
  $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  $SUDO systemctl enable --now docker
}

ensure_command_or_install() {
  local cmd="$1"; shift
  local pkg="$1"; shift || pkg="$cmd"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    info "Installing package '$pkg'"
    $SUDO apt-get update -y
    $SUDO apt-get install -y --no-install-recommends "$pkg"
  fi
}

prepare_image_choice() {
  if [ -n "${IMAGE:-}" ]; then
    info "Using user-specified image: $IMAGE"; return
  fi
  if [ "${BUILD_LOCAL}" = "1" ]; then
    IMAGE="$IMAGE_DEFAULT"; info "BUILD_LOCAL=1; will build $IMAGE"; return
  fi
  if [ -n "${IMAGE_REGISTRY}" ]; then
    remote_suffix="${DEFAULT_REMOTE_IMAGE#ghcr.io/}"
    IMAGE="${IMAGE_REGISTRY%/}/${remote_suffix}"
  else
    IMAGE="$DEFAULT_REMOTE_IMAGE"
  fi
  info "Defaulting to remote image: $IMAGE"
}

build_or_pull_image() {
  if [ "${BUILD_LOCAL}" = "1" ] || [ "${IMAGE}" = "${IMAGE_DEFAULT}" ]; then
    if [ -f "$REPO_DIR/ssh-forward/Dockerfile" ]; then
      if command -v docker >/dev/null 2>&1 && docker buildx version >/dev/null 2>&1; then
        info "Building local image with buildx: $IMAGE"
        $SUDO docker buildx build --load -t "$IMAGE" -f "$REPO_DIR/ssh-forward/Dockerfile" "$REPO_DIR"
      else
        info "buildx not available; falling back to docker build"
        $SUDO docker build -t "$IMAGE" -f "$REPO_DIR/ssh-forward/Dockerfile" "$REPO_DIR"
      fi
    else
      err "Missing $REPO_DIR/ssh-forward/Dockerfile"; exit 1
    fi
  else
    info "Pulling image: $IMAGE"
    $SUDO docker pull "$IMAGE"
  fi
}

stop_remove_existing_container() {
  if $SUDO docker ps -a --format '{{.Names}}' | grep -xq "$CONTAINER_NAME"; then
    info "Stopping/removing existing container: $CONTAINER_NAME"
    $SUDO docker stop "$CONTAINER_NAME" || true
    $SUDO docker rm "$CONTAINER_NAME" || true
  fi
}

run_container() {
  local envs=()
  [ -n "$LISTEN_ADDR" ] && envs+=( -e LISTEN_ADDR="$LISTEN_ADDR" )
  [ -n "$UPSTREAM_ADDR" ] && envs+=( -e UPSTREAM_ADDR="$UPSTREAM_ADDR" )
  [ -n "$DIAL_TIMEOUT" ] && envs+=( -e DIAL_TIMEOUT="$DIAL_TIMEOUT" )
  [ -n "$IDLE_TIMEOUT" ] && envs+=( -e IDLE_TIMEOUT="$IDLE_TIMEOUT" )
  [ -n "$TCP_KEEPALIVE" ] && envs+=( -e TCP_KEEPALIVE="$TCP_KEEPALIVE" )
  [ -n "$MAX_CONNS" ] && envs+=( -e MAX_CONNS="$MAX_CONNS" )

  info "Running container $CONTAINER_NAME (image: $IMAGE) host:$HOST_PORT -> container:$CONTAINER_PORT"
  $SUDO docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    --restart unless-stopped \
    "${envs[@]}" \
    "$IMAGE"
}

# Main
ensure_root
check_os

ensure_command_or_install curl curl
ensure_command_or_install gpg gnupg
ensure_command_or_install lsb_release lsb-release || true

install_docker

if ! $SUDO docker info >/dev/null 2>&1; then
  info "Waiting for Docker daemon..."; sleep 2
fi

prepare_image_choice
build_or_pull_image
CONTAINER_NAME="${CONTAINER_NAME:-$CONTAINER_NAME_DEFAULT}"
stop_remove_existing_container
run_container

info "Deployment complete. View logs: docker logs -f $CONTAINER_NAME"

