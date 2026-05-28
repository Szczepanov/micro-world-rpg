#!/usr/bin/env bash
# run_tests.sh - Execute the GUT test suite headlessly.
# Usage: ./run_tests.sh [GODOT_BINARY]

set -euo pipefail

GODOT_BIN="${1:-godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v "${GODOT_BIN}" &>/dev/null; then
	echo "Godot binary not found: '${GODOT_BIN}'" >&2
	exit 2
fi

echo "============================================"
echo "micro-world-rpg - GUT Headless Test Runner"
echo "Godot: $(${GODOT_BIN} --version 2>/dev/null || echo 'unknown')"
echo "Project: ${PROJECT_DIR}"
echo "============================================"

"${GODOT_BIN}" \
	--headless \
	--path "${PROJECT_DIR}" \
	-s addons/gut/gut_cmdline.gd \
	-gdir=res://test/unit/ \
	-gprefix=test_ \
	-gsuffix=.gd \
	-glog=1 \
	-gexit

EXIT_CODE=$?

if [ "${EXIT_CODE}" -eq 0 ]; then
	echo "All tests passed."
else
	echo "Test suite failed (exit code: ${EXIT_CODE})."
fi

exit "${EXIT_CODE}"
