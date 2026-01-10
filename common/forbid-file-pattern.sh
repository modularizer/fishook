#!/usr/bin/env bash
set -euo pipefail

# Usage: forbid-file-pattern.sh <pattern> <error-message>
# Checks if the file path matches pattern and raises error if it does
# Useful for preventing certain file names from being committed

PATTERN="${1:-}"
MESSAGE="${2:-file name matches forbidden pattern}"

[[ -z "$PATTERN" ]] && echo "Usage: forbid-file-pattern.sh <pattern> <message>" >&2 && exit 1

if [[ "${FISHOOK_PATH:-}" =~ $PATTERN ]]; then
  raise "$MESSAGE"
fi
