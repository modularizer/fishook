#!/usr/bin/env bash
set -euo pipefail

modify_commit_message(){
  local pattern="$2"
  MSG_FILE="$1"
  sed -i "$pattern" "$MSG_FILE"
}

# If executed (not sourced), run with CLI args.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  modify_commit_message "$@"
fi
