#!/usr/bin/env bash
set -euo pipefail

# Usage: forbid-pattern.sh <pattern> <error-message>
# Searches new() content for pattern and raises error if found, e.g. password check

PATTERN="${1:-}"
MESSAGE="${2:-contains forbidden pattern}"

[[ -z "$PATTERN" ]] && echo "Usage: forbid-pattern.sh <pattern> <message>" >&2 && exit 1

if new | grep -qE "$PATTERN"; then
  raise "$MESSAGE"
fi

