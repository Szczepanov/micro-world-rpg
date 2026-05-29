#!/usr/bin/env bash
# =============================================================================
# build_server.sh — Automated Linux Headless Server Compiler
# Project: Pocket Realms (micro-world-rpg)
# Usage: bash build_server.sh [godot_binary_path]
# =============================================================================
set -euo pipefail

# ---------- Configuration ---------------------------------------------------
PRESET_NAME="Linux Dedicated Server"
OUTPUT_DIR="build/server"
OUTPUT_BINARY="$OUTPUT_DIR/server.x86_64"
PCK_FILE="$OUTPUT_DIR/server.pck"
EXPORT_PRESETS_CFG="export_presets.cfg"

# Allow overriding the Godot binary via argument or environment variable.
GODOT_BIN="${1:-${GODOT_BIN:-godot}}"

# ---------- Colour helpers --------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[BUILD]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------- 1. Guard: Verify Godot binary -----------------------------------
log_info "Checking for Godot binary at: '$GODOT_BIN'"
if ! command -v "$GODOT_BIN" &>/dev/null && [ ! -x "$GODOT_BIN" ]; then
    log_error "Godot binary not found. Set GODOT_BIN env var or pass path as arg."
    log_error "Example: GODOT_BIN=/opt/godot/godot bash build_server.sh"
    exit 1
fi
GODOT_VERSION=$("$GODOT_BIN" --version 2>&1 | head -n1 || true)
log_info "Godot version: $GODOT_VERSION"

# ---------- 2. Create output directory --------------------------------------
log_info "Creating output directory: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ---------- 3. Write / refresh the export preset ----------------------------
# This block is idempotent: it replaces any existing [preset.N] block whose
# name matches PRESET_NAME, or appends a new one if none exists.
log_info "Writing 'Linux Dedicated Server' export preset to $EXPORT_PRESETS_CFG"

PRESET_BLOCK=$(cat <<'PRESET'
[preset.1]

name="Linux Dedicated Server"
platform="Linux"
runnable=false
dedicated_server=true
custom_features=""
export_filter="custom_resources"
include_filter=""
exclude_filter=""

[preset.1.options]

; ---- ASSET STRIPPING: drop all graphical & audio data packs ----
; Renders, materials, 3D meshes, textures, and audio streams are
; not needed by a headless process. Stripping them reduces the PCK
; footprint by 60–80% vs. a standard export.
custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"

; Script-only mode: exclude all non-script/non-resource assets.
script/export_mode=2
script/script_key=""

; Explicit exclusion globs — belt-and-suspenders against asset bleed.
exclude_filter="*.png, *.jpg, *.jpeg, *.webp, *.basis, *.dds, *.svg, \
*.ogg, *.mp3, *.wav, *.opus, \
*.glb, *.gltf, *.fbx, *.obj, \
*.material, *.tres, *.shader, \
*.tscn"

; Include only scripts, autoloads, configs, and exported data.
include_filter="*.gd, *.gdscript, *.gdc, *.res, project.godot, \
export_presets.cfg, *.gdextension, *.so, plugin.cfg"
PRESET
)

# If the file doesn't exist yet, touch it.
touch "$EXPORT_PRESETS_CFG"

# Clean up any existing [preset.1] blocks using inline Python for robust, idempotent replacement
python3 -c '
import re
cfg = "'"$EXPORT_PRESETS_CFG"'"
try:
    with open(cfg, "r") as f:
        text = f.read()
    # Split by [preset.N] headers
    parts = re.split(r"(^\[preset\.\d+\])", text, flags=re.MULTILINE)
    new_parts = []
    i = 0
    while i < len(parts):
        if parts[i].startswith("[preset.1]"):
            # Skip this header and the content that follows it
            i += 2
        else:
            new_parts.append(parts[i])
            i += 1
    cleaned = "".join(new_parts).rstrip() + "\n\n"
    with open(cfg, "w") as f:
        f.write(cleaned)
except Exception as e:
    print("Warning during export_presets cleanup:", e)
'

echo "$PRESET_BLOCK" >> "$EXPORT_PRESETS_CFG"
log_info "Preset block written successfully."

# ---------- 4. Execute headless export --------------------------------------
log_info "Running Godot headless export-release..."
log_info "  Preset : '$PRESET_NAME'"
log_info "  Output : '$OUTPUT_BINARY'"

set +e
"$GODOT_BIN" \
    --headless \
    --export-release "$PRESET_NAME" "$OUTPUT_BINARY" \
    2>&1 | tee /tmp/godot_build.log

GODOT_EXIT="${PIPESTATUS[0]}"
set -e

if [ "$GODOT_EXIT" -ne 0 ] && [ ! -f "$OUTPUT_BINARY" ]; then
    log_error "Godot export failed with exit code $GODOT_EXIT."
    log_error "Last 20 lines of build log:"
    tail -n 20 /tmp/godot_build.log >&2
    exit "$GODOT_EXIT"
fi

# ---------- 5. Verify output artifact ---------------------------------------
if [ ! -f "$OUTPUT_BINARY" ]; then
    log_error "Export succeeded but binary '$OUTPUT_BINARY' was not created."
    exit 1
fi

# ---------- 6. Apply execution permissions ----------------------------------
log_info "Applying execute permission to binary..."
chmod +x "$OUTPUT_BINARY"

# ---------- 7. Report artifact size ----------------------------------------
BINARY_SIZE=$(du -sh "$OUTPUT_BINARY" | cut -f1)
PCK_SIZE="N/A"
if [ -f "$PCK_FILE" ]; then
    PCK_SIZE=$(du -sh "$PCK_FILE" | cut -f1)
fi

log_info "=== BUILD COMPLETE ==="
log_info "  Binary : $OUTPUT_BINARY ($BINARY_SIZE)"
log_info "  PCK    : $PCK_FILE ($PCK_SIZE)"
log_info "  Ready to containerize with: docker build -t pocket-realms-server ."
