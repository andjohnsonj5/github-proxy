#!/usr/bin/env bash
set -euo pipefail

# One-click deploy script for Debian 12 (uses Docker)
# - Installs Docker if missing (uses Docker official repo)
# - Builds local image from proxy/ or pulls IMAGE if set
# - Runs container with restart policy

# Repo root (script may be run from other working dir)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_DEFAULT="github-proxy:local"
CONTAINER_NAME_DEFAULT="github-proxy"
HOST_PORT_DEFAULT=8000
CONTAINER_PORT_DEFAULT=8000

IMAGE="${IMAGE:-}"
CONTAINER_NAME="${CONTAINER_NAME:-$CONTAINER_NAME_DEFAULT}"
HOST_PORT="${HOST_PORT:-$HOST_PORT_DEFAULT}"
CONTAINER_PORT="${CONTAINER_PORT:-$CONTAINER_PORT_DEFAULT}"

# Helpers
info(){ echo -e "[INFO] $*"; }
err(){ echo -e "[ERROR] $*" >&2; }

ensure_root() {
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO=sudo
    else
      err "This script must be run as root or with sudo. Install sudo and retry."; exit 1
    fi
  else
    SUDO=""
  fi
}

ensure_command_or_install() {
  local cmd="$1"; shift
  local pkg="$1"; shift || pkg="$cmd"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    info "Installing package '$pkg' (required for command '$cmd')"
    $SUDO apt-get update -y
    $SUDO apt-get install -y --no-install-recommends "$pkg"
  fi
}

check_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "${ID:-}" != "debian" ] || [ "${VERSION_ID:-}" != "12" ]; then
      echo "Warning: this script targets Debian 12. Detected: ${ID:-} ${VERSION_ID:-}"
      echo "Proceeding anyway..."
    fi
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    info "Docker already installed"
    return
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

build_or_pull_image() {
  if [ -n "${IMAGE:-}" ]; then
    info "Pulling image: $IMAGE"
    $SUDO docker pull "$IMAGE"
  else
    # build local
    if [ -f "$REPO_DIR/proxy/Dockerfile" ]; then
      info "Building local image: $IMAGE_DEFAULT from $REPO_DIR/proxy/Dockerfile"
      $SUDO docker build -t "$IMAGE_DEFAULT" -f "$REPO_DIR/proxy/Dockerfile" "$REPO_DIR/proxy"
      IMAGE="$IMAGE_DEFAULT"
    else
      err "No $REPO_DIR/proxy/Dockerfile found and no IMAGE specified. Aborting."; exit 1
    fi
  fi
}

stop_remove_existing_container() {
  if $SUDO docker ps -a --format '{{.Names}}' | grep -xq "$CONTAINER_NAME"; then
    info "Stopping and removing existing container: $CONTAINER_NAME"
    $SUDO docker stop "$CONTAINER_NAME" || true
    $SUDO docker rm "$CONTAINER_NAME" || true
  fi
}

run_container() {
  info "Running container: $CONTAINER_NAME (image: $IMAGE) -> host:$HOST_PORT -> container:$CONTAINER_PORT"
  $SUDO docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    --restart unless-stopped \
    "$IMAGE"
}

# Main
ensure_root
check_os

# Ensure minimal commands
ensure_command_or_install curl curl
ensure_command_or_install gpg gnupg
ensure_command_or_install lsb_release lsb-release || true
ensure_command_or_install apt-get apt
ensure_command_or_install git git

install_docker

# Wait for docker daemon
if ! $SUDO docker info >/dev/null 2>&1; then
  info "Waiting for Docker daemon to start..."
  sleep 2
fi

build_or_pull_image

# Set CONTAINER_NAME if empty
CONTAINER_NAME="${CONTAINER_NAME:-$CONTAINER_NAME_DEFAULT}"

stop_remove_existing_container
run_container

info "Deployment complete. Use 'docker logs -f $CONTAINER_NAME' to view logs."
