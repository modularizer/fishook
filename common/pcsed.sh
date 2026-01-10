#!/usr/bin/env bash
set -euo pipefail

pcsed() {
  local modify_flags=()
  local sed_expr=""

  for arg in "$@"; do
    case "$arg" in
      --index-only|--staged-only|--worktree-only|--local-only|--no-stage)
        modify_flags+=("$arg")
        ;;
      -*)
        echo "pcsed: unknown flag: $arg" >&2
        return 2
        ;;
      *)
        sed_expr="$arg"
        ;;
    esac
  done

  [[ -n "$sed_expr" ]] || {
    echo "usage: pcsed [modify-flags...] <sed-expr>" >&2
    return 2
  }

  local original result
  original="$(new)"
  result="$(printf '%s' "$original" | sed -E "$sed_expr")"

  if [[ "$result" != "$original" ]]; then
    echo "fishook: sed-modify applied: $sed_expr" >&2
    modify "${modify_flags[@]}" "$result"
  fi
}

# If executed (not sourced), run pcsed with CLI args.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  pcsed "$@"
fi
