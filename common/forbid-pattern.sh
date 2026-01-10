#!/usr/bin/env bash
set -euo pipefail

forbid_pattern() {
  local pattern="${1:-}"
  local message="${2:-contains forbidden pattern}"

  [[ -n "$pattern" ]] || {
    echo "usage: forbid_pattern <pattern> <message>" >&2
    return 1
  }

  if new | grep -qE "$pattern"; then
    raise "$message"
  fi
}

# If executed directly, run it.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  forbid_pattern "$@"
fi
