#!/usr/bin/env bash
set -euo pipefail

# Usage: ensure-executable.sh
# Ensures the current file ($FISHOOK_PATH) is executable
# Typically used with applyTo filter like: "applyTo": ["*.sh"]

[[ -z "${FISHOOK_PATH:-}" ]] && echo "Error: FISHOOK_PATH not set" >&2 && exit 1

FILE="$FISHOOK_PATH"

# Check if file exists and is not already executable
if [[ -f "$FILE" && ! -x "$FILE" ]]; then
  chmod +x "$FILE"
  git add "$FILE"
  echo "✓ Made executable: $FILE"
fi
