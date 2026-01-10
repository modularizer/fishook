#!/usr/bin/env bash
# fishook scope helpers
# Intended to be sourced into the hook execution shell.

set -euo pipefail

fishook_old_path() { printf "%s\n" "${FISHOOK_SRC:-${FISHOOK_PATH:-}}"; }
fishook_new_path() { printf "%s\n" "${FISHOOK_DST:-${FISHOOK_PATH:-}}"; }

old() {
  local p
  p="$(fishook_old_path)"; [[ -z "$p" ]] && return 0
  if [[ -n "${FISHOOK_OLD_OID:-}" ]]; then
    git show "${FISHOOK_OLD_OID}:$p" 2>/dev/null || true
  else
    git show "HEAD:$p" 2>/dev/null || true
  fi
}

new() {
  local p
  p="$(fishook_new_path)"; [[ -z "$p" ]] && return 0
  if [[ -n "${FISHOOK_NEW_OID:-}" ]]; then
    git show "${FISHOOK_NEW_OID}:$p" 2>/dev/null || true
  else
    # ":" means index (staged); fall back to worktree if not available
    git show ":$p" 2>/dev/null || cat -- "$p" 2>/dev/null || true
  fi
}

diff() {
  local p_old p_new p
  p_old="$(fishook_old_path)"
  p_new="$(fishook_new_path)"
  p="${p_new:-$p_old}"
  [[ -z "$p" ]] && return 0

  if [[ -n "${FISHOOK_OLD_OID:-}" && -n "${FISHOOK_NEW_OID:-}" ]]; then
    git diff --no-color --text "${FISHOOK_OLD_OID}" "${FISHOOK_NEW_OID}" -- "$p" 2>/dev/null || true
  else
    git diff --cached --no-color --text -- "$p" 2>/dev/null || true
  fi
}

modify() {
  local mode="both"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --index-only|--staged-only) mode="index"; shift ;;
      --worktree-only|--local-only) mode="worktree"; shift ;;
      --no-stage) mode="worktree_nostage"; shift ;;
      --) shift; break ;;
      -*) echo "fishook: modify: unknown flag: $1" >&2; return 2 ;;
      *) break ;;
    esac
  done

  local p
  p="$(fishook_new_path)"; [[ -z "$p" ]] && return 0

  # Prefer stdin (robust). If an arg is provided, use it.
  local text
  if [[ $# -gt 0 ]]; then
    text="$1"
  else
    text="$(cat)"
  fi

  # Preserve executable bit if tracked; else infer from current worktree.
  local idx_mode
  idx_mode="$(git ls-files -s -- "$p" 2>/dev/null | awk 'NR==1{print $1}')"
  if [[ -z "$idx_mode" ]]; then
    if [[ -x "$p" ]]; then idx_mode="100755"; else idx_mode="100644"; fi
  fi

  if [[ "$mode" == "index" ]]; then
    local blob
    blob="$(printf '%s' "$text" | git hash-object -w --stdin)" || return 1
    git update-index --cacheinfo "${idx_mode},${blob},${p}" || return 1
    return 0
  fi

  mkdir -p "$(dirname -- "$p")" 2>/dev/null || true
  printf '%s' "$text" > "$p" || return 1

  if [[ "$idx_mode" == "100755" ]]; then
    chmod +x "$p" 2>/dev/null || true
  else
    chmod -x "$p" 2>/dev/null || true
  fi

  if [[ "$mode" != "worktree_nostage" ]]; then
    git add -- "$p" || return 1
  fi
}

raise() {
  echo "❌ ${FISHOOK_HOOK:-hook} failed on ${FISHOOK_PATH:-${FISHOOK_DST:-${FISHOOK_SRC:-?}}}: $1" >&2
  exit 1
}

source "$FISHOOK_COMMON/pcsed.sh"
source "$FISHOOK_COMMON/forbid-pattern.sh"
source "$FISHOOK_COMMON/forbid-file-pattern.sh"
source "$FISHOOK_COMMON/ensure-executable.sh"
source "$FISHOOK_COMMON/modify-commit-message.sh"

export -f fishook_old_path fishook_new_path old new diff modify raise pcsed forbid_pattern forbid_file_pattern ensure_executable modify_commit_message
