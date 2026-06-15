#!/usr/bin/env bash
# =============================================================================
# build_and_containerize.sh — Unified Build & Docker Image Creation
# Project: Pocket Realms (micro-world-rpg)
# Usage: bash build_and_containerize.sh [godot_binary_path]
# =============================================================================

set -euo pipefail

# ---------- Configuration ---------------------------------------------------
GODOT_BIN="${1:-${GODOT_BIN:-godot}}"
IMAGE_NAME="pocket-realms-server"

# ---------- Colour helpers --------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[BUILD-CONTAINER]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------- Step 1: Build Server Binary ------------------------------------
log_info "=== Step 1: Building Server Binary ==="
if ! bash build_server.sh "$GODOT_BIN"; then
    log_error "Server build failed. Aborting containerization."
    exit 1
fi
log_info "Server binary built successfully."

# ---------- Step 2: Build Docker Image ------------------------------------
log_info "=== Step 2: Building Docker Image ==="
log_info "Image name: $IMAGE_NAME"

if ! docker build -t "$IMAGE_NAME" .; then
    log_error "Docker build failed. Check Dockerfile and build context."
    exit 1
fi

log_info "=== COMPLETE ==="
log_info "Server binary: build/server/server.x86_64"
log_info "Docker image: $IMAGE_NAME"
log_info ""
log_info "Run container with:"
log_info "  docker run -p 8080:8080/udp $IMAGE_NAME"
