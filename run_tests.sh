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

if [ -f "${PROJECT_DIR}/addons/gut/addons/gut/gut_cmdln.gd" ] || [ -f "${PROJECT_DIR}/addons/gut/addons/gut/gut_cmdline.gd" ]; then
	echo "Detected nested GUT layout at addons/gut/addons/gut (repo root checked out at addons/gut)." >&2
	echo "GUT expects files directly under addons/gut/, so this layout fails at runtime." >&2
	echo "Reinstall submodule at addons/ (not addons/gut):" >&2
	echo "  git submodule deinit -f addons/gut" >&2
	echo "  git rm -f addons/gut" >&2
	echo "  rm -rf .git/modules/addons/gut" >&2
	echo "  git submodule add https://github.com/bitwes/Gut.git addons" >&2
	exit 2
fi

GUT_SCRIPT=""
for candidate in "addons/gut/gut_cmdline.gd" "addons/gut/gut_cmdln.gd"
do
	if [ -f "${PROJECT_DIR}/${candidate}" ]; then
		GUT_SCRIPT="${candidate}"
		break
	fi
done

if [ -z "${GUT_SCRIPT}" ]; then
	echo "GUT command-line script not found." >&2
	echo "Checked:" >&2
	echo "  ${PROJECT_DIR}/addons/gut/gut_cmdline.gd" >&2
	echo "  ${PROJECT_DIR}/addons/gut/gut_cmdln.gd" >&2
	echo "Install GUT into addons/gut (plugin root), e.g.:" >&2
	echo "  git submodule add https://github.com/bitwes/Gut.git addons" >&2
	exit 2
fi

echo "============================================"
echo "micro-world-rpg - GUT Headless Test Runner"
echo "Godot: $(${GODOT_BIN} --version 2>/dev/null || echo 'unknown')"
echo "Project: ${PROJECT_DIR}"
echo "============================================"

echo "Running import warm-up..."
"${GODOT_BIN}" --headless --display-driver headless --path "${PROJECT_DIR}" --import >/dev/null 2>&1 || true

LOG_FILE="$(mktemp)"
set +e
"${GODOT_BIN}" \
	--headless \
	--display-driver headless \
	--path "${PROJECT_DIR}" \
	-s "${GUT_SCRIPT}" \
	-gdir=res://test/unit/ \
	-gprefix=test_ \
	-gsuffix=.gd \
	-glog=1 \
	-gexit 2>&1 | tee "${LOG_FILE}"
EXIT_CODE=${PIPESTATUS[0]}
set -e

if grep -Fq "Some GUT class_names have not been imported" "${LOG_FILE}"; then
	echo "GUT import cache is not ready. Re-run after a successful headless import." >&2
	EXIT_CODE=2
fi

rm -f "${LOG_FILE}"

if [ "${EXIT_CODE}" -eq 0 ]; then
	echo "All tests passed."
else
	echo "Test suite failed (exit code: ${EXIT_CODE})."
fi

exit "${EXIT_CODE}"
