# =============================================================================
# Dockerfile — Pocket Realms: Dedicated Server (Ultra-Lean)
# Build context: project root AFTER running build_server.sh
# Final image target: ~60–80 MB (no Godot editor, no X11, no Mesa)
# =============================================================================

# ---- Stage 1: Dependency installer ----------------------------------------
# Use a builder stage purely to resolve and cache apt packages.
FROM debian:bookworm-slim AS runtime-deps

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core C runtime — required by every ELF binary on Linux
    libc6 \
    # TLS/SSL for any HTTPS calls Godot makes (OS.request_permissions, etc.)
    libssl3 \
    ca-certificates \
    # GDScript relies on libgcc_s for exception unwinding
    libgcc-s1 \
    # FreeType font rasteriser (used by headless Label nodes internally)
    libfreetype6 \
    # Godot's PCM audio backend — present even in headless, safe to include
    # (costs <1 MB; removing it causes a non-fatal startup warning)
    libasound2 \
    # D-Bus: required by Godot's OS singleton on Linux
    libdbus-1-3 \
    # Unicode bidirectional text (FriBidi — required by the scene parser)
    libfribidi0 \
    # HarfBuzz text shaper (required even if no text is rendered)
    libharfbuzz0b \
    && rm -rf /var/lib/apt/lists/*

# ---- Stage 2: Minimal runtime image ----------------------------------------
FROM debian:bookworm-slim

# Copy only the installed shared libraries from Stage 1 to keep this layer
# completely free of apt caches, package indices, and transitive toolchains.
COPY --from=runtime-deps /usr/lib/x86_64-linux-gnu/ /usr/lib/x86_64-linux-gnu/
COPY --from=runtime-deps /lib/x86_64-linux-gnu/ /lib/x86_64-linux-gnu/
COPY --from=runtime-deps /etc/ssl/ /etc/ssl/
COPY --from=runtime-deps /etc/ca-certificates/ /etc/ca-certificates/

# Create a non-root service user for security hardening.
RUN groupadd --system gameserver && \
    useradd --system --create-home --home-dir /home/gameserver --gid gameserver gameserver

# Ensure permissions are recursively applied across both app and home areas
RUN mkdir -p /app /home/gameserver && \
    chown -R gameserver:gameserver /app /home/gameserver

WORKDIR /app

# Copy the pre-compiled server binary and its PCK data pack.
# Both files MUST be in the same directory (Godot resolves PCK by proximity).
COPY build/server/server.x86_64 ./server.x86_64
COPY build/server/server.pck    ./server.pck

# Copy the GDExtension files for the SQLite database driver.
# These are referenced from res://addons/godot-sqlite/ and must be available at runtime.
COPY addons/godot-sqlite/ ./addons/godot-sqlite/

# Ensure the binary is executable (build_server.sh already does this,
# but Docker COPY strips the setuid bit — re-apply explicitly).
RUN chmod +x ./server.x86_64

# Transfer ownership to the non-root user.
RUN chown -R gameserver:gameserver /app

USER gameserver

# --- Networking ---
# Port 8080/UDP — matches SERVER_PORT in network.gd.
# ENet (Godot's default multiplayer transport) uses UDP exclusively.
# Map as: docker run -p 8080:8080/udp pocket-realms-server
EXPOSE 8080/udp

# --- Health Check ---
# Since UDP has no handshake, we verify the process is alive instead.
# The server exits non-zero on fatal errors, so this sentinel is reliable.
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD pgrep -x server.x86_64 > /dev/null || exit 1

# --- Entrypoint ---
# Exec form (no shell wrapper) ensures SIGTERM propagates directly to Godot,
# allowing the engine's _notification(NOTIFICATION_WM_CLOSE_REQUEST) to fire
# for graceful shutdown and final DB flush (see Milestone 4.3).
CMD ["./server.x86_64", "--headless", "--server"]
