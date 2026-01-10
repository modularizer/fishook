#!/usr/bin/env bash
set -euo pipefail

ensure_executable() {

  
  local p="${1:-}"
  
    if [[ -z "$p" ]]; then
      if [[ -n "${FISHOOK_DST:-}" ]]; then
        p="$FISHOOK_DST"
      elif [[ -n "${FISHOOK_PATH:-}" ]]; then
        p="$FISHOOK_PATH"
      elif [[ -n "${FISHOOK_SRC:-}" ]]; then
        p="$FISHOOK_SRC"
      fi
    fi

    [[ -n "${p:-}" ]] || {
        echo "ensure_executable: FISHOOK_PATH not set" >&2
        return 1
      }


  if [[ -f "$p" && ! -x "$p" ]]; then
    chmod +x "$p"
    git add "$p"
    echo "✓ Made executable: $p"
  fi
}

# If executed directly, run it.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ensure_executable "$@"
fi
