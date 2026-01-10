#!/usr/bin/env bash
set -euo pipefail

ensure_executable() {
  [[ -n "${FISHOOK_PATH:-}" ]] || {
    echo "ensure_executable: FISHOOK_PATH not set" >&2
    return 1
  }

  local file="$FISHOOK_PATH"

  if [[ -f "$file" && ! -x "$file" ]]; then
    chmod +x "$file"
    git add "$file"
    echo "✓ Made executable: $file"
  fi
}

# If executed directly, run it.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ensure_executable "$@"
fi
