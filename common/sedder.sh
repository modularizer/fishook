#!/usr/bin/env bash
set -euo pipefail

# usage:
#   sed-modify.sh [modify-flags...] <sed-expr>
#
# examples:
#   sed-modify.sh 's/foo/bar/g'
#   sed-modify.sh --index-only 's/[ \t]*$//'

modify_flags=()

while [[ $# -gt 1 ]]; do
  case "$1" in
    --index-only|--staged-only|--worktree-only|--local-only|--no-stage)
      modify_flags+=("$1")
      shift
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -eq 1 ]] || { echo "usage: sed-modify.sh [modify-flags...] <sed-expr>" >&2; exit 2; }

sed_expr="$1"

# Get current content, apply sed, and write back
result="$(
  new | sed -E "$sed_expr"
)"

modify "${modify_flags[@]}" "$result"
