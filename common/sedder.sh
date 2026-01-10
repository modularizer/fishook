#!/usr/bin/env bash
set -euo pipefail

modify_flags=()
sed_expr=""

for arg in "$@"; do
  case "$arg" in
    --index-only|--staged-only|--worktree-only|--local-only|--no-stage)
      modify_flags+=("$arg")
      ;;
    -*)
      echo "sed-modify.sh: unknown flag: $arg" >&2
      exit 2
      ;;
    *)
      sed_expr="$arg"
      ;;
  esac
done

[[ -n "$sed_expr" ]] || {
  echo "usage: sed-modify.sh [modify-flags...] <sed-expr>" >&2
  exit 2
}

original="$(new)"
result="$(printf '%s' "$original" | sed -E "$sed_expr")"

if [[ "$result" != "$original" ]]; then
  echo "fishook: sed-modify applied: $sed_expr" >&2
  modify "${modify_flags[@]}" "$result"
fi
