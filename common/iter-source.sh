#!/usr/bin/env bash

iter_source() {
  local dir="$1"

  [[ -d "$dir" ]] || return 1

  for file in "$dir"/*.sh; do
    [[ -f "$file" ]] && source "$file"
  done
}

# allow: source iter-source.sh path/to/dir
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  iter_source "$@"
fi