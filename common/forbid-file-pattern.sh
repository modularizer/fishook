#!/usr/bin/env bash
set -euo pipefail

forbid_file_pattern() {
  local pattern="${1:-}"
  local message="${2:-file name matches forbidden pattern}"

  [[ -n "$pattern" ]] || {
    echo "usage: forbid_file_pattern <pattern> <message>" >&2
    return 1
  }

  if [[ "${FISHOOK_PATH:-}" =~ $pattern ]]; then
    raise "$message"
  fi
}

# If executed directly, run it.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  forbid_file_pattern "$@"
fi
