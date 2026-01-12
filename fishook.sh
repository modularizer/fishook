#!/usr/bin/env bash
# fishook.sh
#
# fishook = tiny git hook runner driven by a JSON file.
#
# Usage:
#   fishook install                     [--config /path/to/fishook.json] [--hooks-path PATH]     # install all hooks
#   fishook uninstall                   [--hooks-path PATH]                                      # uninstall all hooks
#   fishook list                                                                                 # lists all hooks
#   fishook explain <hook-name>         [--config /path/to/fishook.json] [--hooks-path PATH]     # explain hook + show configured actions
#   fishook <hook-name>  [hook-args...] [--config /path/to/fishook.json] [--dry-run]             # run the hook
#
# fishook.json:
#   - Put a fishook.json in your repo (default: <repo-root>/fishook.json)
#   - Keys are git hook names (e.g. "pre-commit", "commit-msg")
#   - Values are:
#       * "string command"
#       * ["cmd1", "cmd2", ...]
#       * {"run": "cmd"} or {"run": ["cmd1","cmd2"]}  ("commands" also works)
#       * object with optional event handlers + optional filters:
#           {
#             "run": ["echo runs once"],
#             "onAdd": ["..."], "onChange": ["..."], "onDelete": ["..."],
#             "onMove": ["..."], "onCopy": ["..."],
#             "onFileEvent": ["..."],
#             "onRefCreate": ["..."], "onRefUpdate": ["..."], "onRefDelete": ["..."],
#             "onRefEvent": ["..."],
#             "onEvent": ["..."],
#             "applyTo": ["glob", ...],   # file-event filter (defaults to all)
#             "skipList": ["glob", ...]   # file-event filter (defaults to none)
#           }
#       * OR an array of such objects ("blocks"):
#           [
#             { "applyTo": ["*.js"], "onAdd": ["..."] },
#             { "applyTo": ["*.ts"], "onAdd": ["..."] }
#           ]
#
# Notes on filters:
#   - applyTo/skipList are evaluated per file event using the "primary" path:
#       add/change/delete -> FISHOOK_PATH
#       move/copy         -> FISHOOK_DST (preferred), else FISHOOK_PATH, else FISHOOK_SRC
#   - For ref events, applyTo/skipList are ignored (for now).

set -euo pipefail

# ---- hooks list (all standard git hooks) ----
ALL_HOOKS=(
  applypatch-msg pre-applypatch post-applypatch
  pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit
  pre-rebase post-checkout post-merge post-rewrite
  pre-push pre-auto-gc
  pre-receive update post-receive post-update push-to-checkout proc-receive
  sendemail-validate fsmonitor-watchman
)

# ---- scope documentation (environment variables and functions) ----
# This section documents all variables and functions available in hook commands.

# ENVIRONMENT VARIABLES:

# FISHOOK_HOOK: The current hook name (e.g., "pre-commit", "pre-push")
# FISHOOK_REPO_ROOT: Absolute path to the repository root directory
# FISHOOK_REPO_NAME: Name of the repository (basename of repo root)
# FISHOOK_GIT_DIR: Absolute path to the .git directory
# FISHOOK_CONFIG_PATH: Path to the fishook.json config file being used
# FISHOOK_CONFIG_DIR: Directory containing the config file (for scoped configs)
# FISHOOK_HOOKS_PATH: Path to the .git/hooks directory
# FISHOOK_COMMON: Path to fishook's common/ directory with helper scripts
# FISHOOK_DRY_RUN: "1" if --dry-run was specified, "0" otherwise
# FISHOOK_CWD: Working directory when fishook was invoked
# FISHOOK_ARGV0: The $0 argument (hook script path)
# FISHOOK_ARGS: Space-separated, shell-quoted hook arguments

# Event-specific variables (set during file/ref events):

# FISHOOK_EVENT_KIND: "file" or "ref" (indicates the type of event)
# FISHOOK_EVENT: Specific event type:
#   File events: "add", "change", "delete", "move", "copy"
#   Ref events: "ref_create", "ref_update", "ref_delete"
# FISHOOK_STATUS: Git status letter (A=add, M=modify, D=delete, Rxxx=rename, Cxxx=copy)

# File event variables:

# FISHOOK_PATH: Relative path to the file (for add/change/delete events)
# FISHOOK_ABS_PATH: Absolute path to the file
# FISHOOK_SRC: Source path (for move/copy events)
# FISHOOK_DST: Destination path (for move/copy events)
# FISHOOK_ABS_SRC: Absolute source path (for move/copy events)
# FISHOOK_ABS_DST: Absolute destination path (for move/copy events)

# Ref event variables:

# FISHOOK_REF: The ref being updated (e.g., "refs/heads/main")
# FISHOOK_OLD_OID: Old commit SHA (or 0000... for new refs)
# FISHOOK_NEW_OID: New commit SHA (or 0000... for deleted refs)
# FISHOOK_REMOTE_NAME: Remote name (pre-push hook only)
# FISHOOK_REMOTE_URL: Remote URL (pre-push hook only)

# Legacy variables (backwards compatibility):

# GIT_HOOK_KEY: Same as FISHOOK_HOOK (deprecated, use FISHOOK_HOOK)
# GIT_HOOK_ARGS: Same as FISHOOK_ARGS (deprecated, use FISHOOK_ARGS)

# FUNCTIONS:

# old(): Print the old version of the current file (from HEAD or FISHOOK_OLD_OID)
#   Usage: old
#   Example: old | grep pattern

# new(): Print the new version of the current file (from index/worktree or FISHOOK_NEW_OID)
#   Usage: new
#   Example: new | grep pattern

# diff(): Show the git diff for the current file
#   Usage: diff
#   Example: diff | grep -q "TODO"

# modify([flags] [text]): Modify the current file in index and/or worktree
#   Usage: modify [--index-only|--worktree-only|--no-stage] [text]
#   Flags:
#     --index-only/--staged-only: Only update the staged version
#     --worktree-only/--local-only: Update worktree and stage it
#     --no-stage: Update worktree but don't stage the change
#   Input: Reads from stdin if no text argument provided
#   Example: new | sed 's/foo/bar/' | modify
#   Example: modify "new content here"

# raise(message): Fail the hook with an error message
#   Usage: raise "error message"
#   Example: raise "commit message too short"

# pcsed([modify-flags] sed-expr): Apply sed transformation to current file
#   Usage: pcsed [modify-flags] <sed-expression>
#   Example: pcsed 's/TODO/DONE/g'
#   Example: pcsed --index-only 's/version = .*/version = 2.0/'

# forbid_pattern(pattern [message]): Fail if file content matches regex pattern
#   Usage: forbid_pattern <pattern> [message]
#   Example: forbid_pattern 'console\.log' "console.log not allowed"
#   Example: forbid_pattern '\bTODO\b'

# forbid_file_pattern(pattern [message]): Fail if filename matches regex pattern
#   Usage: forbid_file_pattern <pattern> [message]
#   Example: forbid_file_pattern '\.orig$' "merge conflict files not allowed"
#   Example: forbid_file_pattern '^\.env' ".env files should not be committed"

# ensure_executable([path]): Make file executable if it isn't already
#   Usage: ensure_executable [path]
#   Example: ensure_executable
#   Example: ensure_executable scripts/deploy.sh

# modify_commit_message(file sed-expr): Modify a commit message file with sed
#   Usage: modify_commit_message <file> <sed-expression>
#   Example: modify_commit_message "$1" 's/^/[PREFIX] /'

# iter_source(directory): Source all .sh files in a directory
#   Usage: iter_source <directory>
#   Example: iter_source "$FISHOOK_COMMON/plugins"

# fishook_old_path(): Print the "old" path (FISHOOK_SRC or FISHOOK_PATH)
#   Usage: fishook_old_path
#   Example: path=$(fishook_old_path)

# fishook_new_path(): Print the "new" path (FISHOOK_DST or FISHOOK_PATH)
#   Usage: fishook_new_path
#   Example: path=$(fishook_new_path)

# ---- globals set by flag parsing ----
CONFIG_PATH=""
HOOKS_PATH=""
DRY_RUN=0

THIS_SCRIPT="${BASH_SOURCE[0]}"
PARENT_DIR="$(dirname "$THIS_SCRIPT")"
GP_DIR="$(dirname "$PARENT_DIR")"
GP_NAME="$(basename "$GP_DIR")"

if [[ "$GP_NAME" == "node_modules" && -d "$GP_NAME/fishook" && -e "$GP_NAME/fishook/fishook.sh" ]]; then
  PARENT_DIR="$GP_NAME/fishook"
  GP_DIR="$(dirname "$PARENT_DIR")"
  GP_NAME="$(basename "$GP_DIR")"
fi
fishook_dir="$(cd "$PARENT_DIR" && pwd)"


# Enable richer globs in [[ "$p" == $glob ]] matching (extglob helps; ** works fine as * * in pattern matching)
shopt -s extglob

# ---- helpers ----
die() { echo "fishook: $*" >&2; exit 2; }

in_git_repo() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }
repo_root() { git rev-parse --show-toplevel 2>/dev/null; }
git_dir() { git rev-parse --git-dir 2>/dev/null; }

default_config_path() {
  local root
  root="$(repo_root)" || die "not inside a git repository"
  echo "${root}/fishook.json"
}

# Find all *fishook*.json files in the repo (for multi-config support)
find_all_configs() {
  local root
  root="$(repo_root)" || die "not inside a git repository"

  # Find all *fishook*.json files (tracked, untracked, and gitignored)
  # Use find with limited depth to avoid performance issues in large repos
  find "$root" -maxdepth 4 -name "*fishook*.json" -type f 2>/dev/null | sort -u
}

default_hooks_path() {
  local gd
  gd="$(git_dir)" || die "not inside a git repository"
  echo "${gd}/hooks"
}

timestamp() { date +"%Y%m%d-%H%M%S"; }

require_jq() { command -v jq >/dev/null 2>&1 || die "requires 'jq'"; }

# Parse flags anywhere in argv and return remaining positional args as NUL-delimited.
# Supports: --config, --hooks-path, --dry-run (plus = forms)
parse_flags() {
  local -a out=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ $# -ge 2 ]] || die "--config requires a path"
        CONFIG_PATH="$2"; shift 2 ;;
      --config=*)
        CONFIG_PATH="${1#*=}"; shift ;;
      --hooks-path)
        [[ $# -ge 2 ]] || die "--hooks-path requires a path"
        HOOKS_PATH="$2"; shift 2 ;;
      --hooks-path=*)
        HOOKS_PATH="${1#*=}"; shift ;;
      --dry-run)
        DRY_RUN=1; shift ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do out+=("$1"); shift; done
        ;;
      -*)
        die "unknown option: $1"
        ;;
      *)
        out+=("$1"); shift ;;
    esac
  done
  printf '%s\0' "${out[@]}"
}

hook_known() {
  local h="$1" x
  for x in "${ALL_HOOKS[@]}"; do
    [[ "$x" == "$h" ]] && return 0
  done
  return 1
}

# Detect whether a hook file is fishook-managed.
is_fishook_stub() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  grep -qE '^# fishook-managed stub' "$file"
}

# Write a stub that calls fishook.sh <hook>, from repo root.
write_stub() {
  local hook="$1"
  local target="$2"
  cat >"$target" <<EOF
#!/usr/bin/env bash
exec "${BASH_SOURCE[0]}" ${hook} "\$@"
EOF
  chmod +x "$target"
}

# For chained hooks, create a stub that runs prev first then fishook.
write_chained_stub() {
  local hook="$1"
  local target="$2"
  local prev="$3"
  cat >"$target" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# fishook-managed stub for ${hook} (chained)
# previous hook preserved at: ${prev}

if [[ -x "${prev}" ]]; then
  "${prev}" "\$@"
fi

exec "${BASH_SOURCE[0]}" ${hook} "\$@"
EOF
  chmod +x "$target"
}

prompt_choice() {
  local hook="$1"
  local file="$2"

  # Allow non-interactive mode via environment variable (useful for testing/automation)
  if [[ -n "${FISHOOK_INSTALL_CHOICE:-}" ]]; then
    echo "$FISHOOK_INSTALL_CHOICE"
    return 0
  fi

  echo
  echo "fishook: found existing hook: ${file}"
  echo "hook: ${hook}"
  echo
  echo "Choose what to do:"
  echo "  1) overwrite (replace existing hook with fishook)"
  echo "  2) chain (rename existing to ${file}.fishook-prev and run it before fishook)"
  echo "  3) backup (rename existing to ${file}.bak.<timestamp>; not chained)"
  echo -n "Enter 1/2/3: " >&2
  read -r choice
  echo "$choice"
}

# Full sample config (small). Written only if missing.
write_sample_config() {
  local path="$1"
  local dir
  dir="$(dirname "$path")"
  mkdir -p "$dir"

  if [[ -e "$path" ]]; then
    echo "fishook: config already exists, leaving it alone: ${path}" >&2
    return 0
  fi

  cat >"$path" <<'EOF'
{
  "_about": "run `fishook list` to see all options",
  "pre-commit": {
    "run": ["echo pre-commit running on $FISHOOK_REPO_NAME"],
    "onFileEvent": "new | grep -qi forbidden && raise \"contains forbidden word\" || true",
    "skipList": ["fishook.json", "fishook.sh"]
  }
}
EOF

  echo "fishook: wrote sample config: ${path}" >&2
}

# ---- JSON helpers ----
# Normalize a JSON value into an array of strings.
# - null/missing -> []
# - string       -> [string]
# - array        -> array
# - object       -> (.run // .commands) normalized similarly (legacy)
normalize_to_cmd_array() {
  jq -c '
    def normalize:
      if . == null then []
      elif type=="string" then [.]
      elif type=="array" then .
      elif type=="object" then (.run // .commands) | normalize
      else error("invalid command value")
      end;
    normalize
  '
}

# Get the raw JSON value for a hook (or empty).
hook_entry_json() {
  local hook="$1"
  jq -c --arg h "$hook" '(.[$h] // empty)' "$CONFIG_PATH"
}

# Does hook entry have "blocks" (object or array-of-objects)?
hook_entry_has_blocks() {
  local hook="$1"
  local entry_type
  entry_type=$(jq -r --arg h "$hook" 'if .[$h] then (.[$h] | type) else "null" end' "$CONFIG_PATH")
  [[ "$entry_type" == "object" || "$entry_type" == "array" ]]
}

# Return a JSON array of "blocks" for a hook:
# - object -> [object]
# - array  -> array
# - else   -> []
hook_blocks_json() {
  local hook="$1"
  jq -c --arg h "$hook" '
    (.[$h] // null) as $e
    | if $e == null then []
      elif ($e|type) == "object" then [$e]
      elif ($e|type) == "array" then $e
      else []
      end
  ' "$CONFIG_PATH"
}

# For legacy/simple "run" support:
# - string/array -> those commands
# - object       -> .run/.commands
# - array        -> concatenate each block's .run/.commands (if present)
hook_run_cmds_json() {
  local hook="$1"
  jq -c --arg h "$hook" '
    def normalize:
      if . == null then []
      elif type=="string" then [.]
      elif type=="array" then .
      elif type=="object" then (.run // .commands) | normalize
      else []
      end;

    (.[$h] // null) as $e
    | if $e == null then []
      elif ($e|type) == "string" then $e | normalize
      elif ($e|type) == "object" then ($e.run // $e.commands) | normalize
      elif ($e|type) == "array" then
        if ($e | length) > 0 and ($e[0] | type) == "object" then
          ( $e | map((.run // .commands) | normalize) | add ) // []
        else
          $e | normalize
        end
      else []
      end
  ' "$CONFIG_PATH"
}

# Extract a key's commands from a single block JSON (object), normalized to JSON array.
block_key_cmds_json() {
  local block_json="$1"
  local key="$2"
  printf '%s' "$block_json" | jq -c --arg k "$key" '
    def normalize:
      if . == null then []
      elif type=="string" then [.]
      elif type=="array" then .
      elif type=="object" then (.run // .commands) | normalize
      else error("invalid command value")
      end;
    (.[ $k ] // null) | normalize
  '
}

# Extract applyTo / skipList from a block, as JSON arrays of strings (possibly empty).
block_apply_to_json() {
  local block_json="$1"
  printf '%s' "$block_json" | jq -c '
    def norm:
      if . == null then []
      elif type=="string" then [.]
      elif type=="array" then .
      else error("applyTo must be string or array")
      end;
    (.applyTo // null) | norm
  '
}

block_skip_list_json() {
  local block_json="$1"
  printf '%s' "$block_json" | jq -c '
    def norm:
      if . == null then []
      elif type=="string" then [.]
      elif type=="array" then .
      else error("skipList must be string or array")
      end;
    (.skipList // null) | norm
  '
}

# Extract top-level "setup" and "source" commands (run before every command).
config_setup_cmds() {
  local setup source_cmd result
  setup=$(jq -r 'if .setup == null then "" elif (.setup | type) == "string" then .setup elif (.setup | type) == "array" then (.setup | join("; ")) else "" end' "$CONFIG_PATH")
  source_cmd=$(jq -r 'if .source == null then "" elif (.source | type) == "string" then "source " + .source elif (.source | type) == "array" then (.source | map("source " + .) | join("; ")) else "" end' "$CONFIG_PATH")

  result=""
  [[ -n "$setup" ]] && result="$setup"
  [[ -n "$source_cmd" ]] && result="${result:+$result; }$source_cmd"
  printf '%s' "$result"
}

# ---- hook explanations (short, useful defaults) ----
hook_explain_text() {
  local h="$1"
  case "$h" in
    applypatch-msg) echo "Runs during git am after extracting a patch commit message; validate/edit the message." ;;
    pre-applypatch) echo "Runs during git am before committing the applied patch; can reject." ;;
    post-applypatch) echo "Runs during git am after committing; notification only." ;;
    pre-commit) echo "Runs before a commit is created; commonly lint/tests/format checks; can reject." ;;
    pre-merge-commit) echo "Runs before creating a merge commit (when merge is clean); can reject." ;;
    prepare-commit-msg) echo "Runs before commit message editor opens; can prefill/edit message." ;;
    commit-msg) echo "Runs after message is written; validate commit message; can reject." ;;
    post-commit) echo "Runs after commit is created; notification only." ;;
    pre-rebase) echo "Runs before rebase starts; can reject." ;;
    post-checkout) echo "Runs after checkout/switch; args old/new/flag." ;;
    post-merge) echo "Runs after merge; arg is squash flag." ;;
    post-rewrite) echo "Runs after commit rewriting; arg is rewrite command; stdin has old/new oids." ;;
    pre-push) echo "Runs before pushing; args remote_name/remote_url; stdin lists ref updates." ;;
    pre-auto-gc) echo "Runs before git gc --auto; can abort." ;;
    pre-receive) echo "Server-side: before accepting pushed refs; stdin old/new/ref triples. Not run on GitHub." ;;
    update) echo "Server-side: per-ref update check; args ref/old/new. Not run on GitHub." ;;
    post-receive) echo "Server-side: after refs updated; stdin old/new/ref triples. Not run on GitHub." ;;
    post-update) echo "Server-side: after refs updated; args are ref names. Not run on GitHub." ;;
    push-to-checkout) echo "Server-side: when pushing to checked-out branch with updateInstead. Not run on GitHub." ;;
    proc-receive) echo "Server-side: advanced receive-pack protocol hook. Not run on GitHub." ;;
    sendemail-validate) echo "Runs during git send-email to validate outgoing patch email; can reject." ;;
    fsmonitor-watchman) echo "Used by core.fsmonitor to speed status; reports changed files." ;;
    *) echo "Unknown hook (or not in fishook's known list)." ;;
  esac
}

# ---- hook-specific scope details ----
hook_scope_details() {
  local h="$1"
  echo "Positional arguments:"
  case "$h" in
    applypatch-msg|commit-msg)
      echo "  \$1  Path to commit message file"
      ;;
    prepare-commit-msg)
      echo "  \$1  Path to commit message file"
      echo "  \$2  Commit message source (message/template/merge/squash/commit)"
      echo "  \$3  Commit SHA (for 'commit' source only)"
      ;;
    post-checkout)
      echo "  \$1  Old HEAD ref (SHA)"
      echo "  \$2  New HEAD ref (SHA)"
      echo "  \$3  Branch checkout flag (1=branch, 0=file)"
      ;;
    post-merge)
      echo "  \$1  Squash merge flag (1=squash, 0=regular)"
      ;;
    pre-push)
      echo "  \$1  Remote name"
      echo "  \$2  Remote URL"
      echo "  stdin: Lines of '<local-ref> <local-sha> <remote-ref> <remote-sha>'"
      ;;
    pre-receive|post-receive)
      echo "  stdin: Lines of '<old-sha> <new-sha> <ref>'"
      ;;
    update)
      echo "  \$1  Ref name"
      echo "  \$2  Old SHA"
      echo "  \$3  New SHA"
      ;;
    post-update)
      echo "  \$*  Updated ref names"
      ;;
    post-rewrite)
      echo "  \$1  Rewrite command (amend/rebase)"
      echo "  stdin: Lines of '<old-sha> <new-sha>'"
      ;;
    pre-rebase)
      echo "  \$1  Upstream branch"
      echo "  \$2  Branch being rebased (if not current)"
      ;;
    sendemail-validate)
      echo "  \$1  Path to email file"
      ;;
    fsmonitor-watchman)
      echo "  \$1  Version number"
      echo "  \$2  Clock token"
      ;;
    pre-commit|pre-merge-commit|post-commit|pre-applypatch|post-applypatch|pre-auto-gc|push-to-checkout|proc-receive)
      echo "  (no arguments)"
      ;;
    *)
      echo "  (unknown hook)"
      ;;
  esac

  echo
  echo "Hook-specific environment variables:"
  case "$h" in
    pre-commit)
      echo "  FISHOOK_EVENT_KIND=file (for onFileEvent handlers)"
      echo "  FISHOOK_EVENT=add|change|delete|move|copy"
      echo "  FISHOOK_STATUS=A|M|D|R*|C*"
      echo "  FISHOOK_PATH, FISHOOK_ABS_PATH (for add/change/delete)"
      echo "  FISHOOK_SRC, FISHOOK_DST (for move/copy)"
      echo "  Available file events: onAdd, onChange, onDelete, onMove, onCopy, onFileEvent"
      echo "  Available functions: old, new, diff, modify, pcsed, forbid_pattern, raise"
      ;;
    post-checkout|post-merge)
      echo "  FISHOOK_EVENT_KIND=file (for onFileEvent handlers)"
      echo "  FISHOOK_EVENT=add|change|delete|move|copy"
      echo "  FISHOOK_PATH, FISHOOK_SRC, FISHOOK_DST (depending on event)"
      echo "  FISHOOK_OLD_OID, FISHOOK_NEW_OID (commit SHAs)"
      echo "  Available file events: onAdd, onChange, onDelete, onMove, onCopy, onFileEvent"
      echo "  Available functions: old, new, diff"
      ;;
    pre-push)
      echo "  FISHOOK_REMOTE_NAME (remote name, from \$1)"
      echo "  FISHOOK_REMOTE_URL (remote URL, from \$2)"
      echo "  FISHOOK_EVENT_KIND=ref (for onRefEvent handlers)"
      echo "  FISHOOK_EVENT=ref_create|ref_update|ref_delete"
      echo "  FISHOOK_REF (ref name)"
      echo "  FISHOOK_OLD_OID, FISHOOK_NEW_OID (commit SHAs)"
      echo "  Available ref events: onRefCreate, onRefUpdate, onRefDelete, onRefEvent"
      ;;
    pre-receive|post-receive)
      echo "  FISHOOK_EVENT_KIND=ref (for onRefEvent handlers)"
      echo "  FISHOOK_EVENT=ref_create|ref_update|ref_delete"
      echo "  FISHOOK_REF (ref name)"
      echo "  FISHOOK_OLD_OID, FISHOOK_NEW_OID (commit SHAs)"
      echo "  Available ref events: onRefCreate, onRefUpdate, onRefDelete, onRefEvent"
      ;;
    update)
      echo "  FISHOOK_EVENT_KIND=ref (for onRefEvent handlers)"
      echo "  FISHOOK_EVENT=ref_create|ref_update|ref_delete"
      echo "  FISHOOK_REF (ref name, from \$1)"
      echo "  FISHOOK_OLD_OID (from \$2), FISHOOK_NEW_OID (from \$3)"
      echo "  Available ref events: onRefCreate, onRefUpdate, onRefDelete, onRefEvent"
      ;;
    commit-msg|prepare-commit-msg)
      echo "  \$1 available as positional arg (commit message file)"
      echo "  Available functions: modify_commit_message, raise"
      ;;
    *)
      echo "  (no hook-specific variables; only base FISHOOK_* vars available)"
      ;;
  esac

  echo
  echo "Base variables (always available):"
  echo "  FISHOOK_HOOK, FISHOOK_REPO_ROOT, FISHOOK_REPO_NAME, FISHOOK_GIT_DIR"
  echo "  FISHOOK_CONFIG_PATH, FISHOOK_HOOKS_PATH, FISHOOK_COMMON"
  echo "  FISHOOK_CWD, FISHOOK_ARGV0, FISHOOK_ARGS, FISHOOK_DRY_RUN"

  echo
  echo "Run 'fishook scope' for full documentation of all functions and variables."
}

# ---- env vars ----
export_base_env() {
  local hook="$1"
  local root gd
  root="$(repo_root)" || root=""
  gd="$(git_dir)" || gd=""

  # Find where fishook.sh is installed and set FISHOOK_COMMON to common/ directory

  export FISHOOK_COMMON="${fishook_dir}/common"
  export FISHOOK_HOOK="$hook"
  export FISHOOK_REPO_ROOT="$root"
  export FISHOOK_REPO_NAME="$(basename "$root" 2>/dev/null || echo "")"
  export FISHOOK_GIT_DIR="$gd"
  export FISHOOK_CONFIG_PATH="$CONFIG_PATH"
  export FISHOOK_HOOKS_PATH="$HOOKS_PATH"
  export FISHOOK_DRY_RUN="$DRY_RUN"
  export FISHOOK_CWD="$(pwd)"
  export FISHOOK_ARGV0="$0"
}

clear_event_env() {
  unset FISHOOK_EVENT_KIND FISHOOK_EVENT FISHOOK_STATUS
  unset FISHOOK_PATH FISHOOK_ABS_PATH
  unset FISHOOK_SRC FISHOOK_DST FISHOOK_ABS_SRC FISHOOK_ABS_DST
  unset FISHOOK_REF
  # NOTE: We intentionally DO NOT unset FISHOOK_OLD_OID / FISHOOK_NEW_OID here
  # because for some hooks we want those to be stable across emitted file events.
  unset FISHOOK_REMOTE_NAME FISHOOK_REMOTE_URL
}

abs_in_repo() {
  local rel="$1"
  [[ -z "${FISHOOK_REPO_ROOT:-}" ]] && echo "$rel" && return 0
  echo "${FISHOOK_REPO_ROOT%/}/${rel}"
}

# ---- glob filtering (block-level applyTo/skipList) ----
fishook_primary_path() {
  # For move/copy, prefer DST; otherwise PATH; otherwise SRC.
  if [[ -n "${FISHOOK_DST:-}" ]]; then
    printf '%s\n' "$FISHOOK_DST"
  elif [[ -n "${FISHOOK_PATH:-}" ]]; then
    printf '%s\n' "$FISHOOK_PATH"
  else
    printf '%s\n' "${FISHOOK_SRC:-}"
  fi
}

fishook_any_match() {
  local s="$1"; shift || true
  local g
  for g in "$@"; do
    [[ -z "$g" ]] && continue
    [[ "$s" == $g ]] && return 0
  done
  return 1
}

fishook_block_allows_path() {
  local p="$1"; shift || true
  local -a apply=() skip=()
  local mode="apply"
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then mode="skip"; shift; continue; fi
    if [[ "$mode" == "apply" ]]; then apply+=("$1"); else skip+=("$1"); fi
    shift
  done

  if [[ "${#apply[@]}" -gt 0 ]]; then
    fishook_any_match "$p" "${apply[@]}" || return 1
  fi
  if [[ "${#skip[@]}" -gt 0 ]]; then
    fishook_any_match "$p" "${skip[@]}" && return 1
  fi
  return 0
}

# ---- execution helpers ----
run_one_cmd() {
  local hook="$1"
  local cmd="$2"
  local context="${3:-}"
  shift 2 || true
  [[ -n "$context" ]] && shift || true
  local -a hook_args=("$@")

  [[ "${FISHOOK_DRY_RUN:-0}" -eq 1 ]] && return 0

  # Setup/source commands (run before everything)
  local setup_cmds
  setup_cmds="$(config_setup_cmds)"
  [[ -n "$setup_cmds" ]] && setup_cmds="${setup_cmds}; "

  # Helper funcs injected into the bash -lc scope (no temp files).
  # after setup_cmds
  local scope_file="${FISHOOK_COMMON}/scope.sh"

  # Capture stderr and exit code to provide better error messages
  local stderr_file exit_code=0
  stderr_file="$(mktemp)"
  trap "rm -f '$stderr_file'" RETURN

  # Pass hook args as bash positional parameters ($1, $2, $3, etc.)
  # so users can access them if needed, but they won't be auto-appended to commands
  if [[ "${#hook_args[@]}" -gt 0 ]]; then
    bash -lc "${setup_cmds}source \"${scope_file}\"; ${cmd}" -- "${hook_args[@]}" 2>"$stderr_file" || exit_code=$?
  else
    bash -lc "${setup_cmds}source \"${scope_file}\"; ${cmd}" 2>"$stderr_file" || exit_code=$?
  fi

  # If command failed, provide detailed error message
  if [[ $exit_code -ne 0 ]]; then
    local stderr_content
    stderr_content="$(cat "$stderr_file")"

    echo "fishook ${hook} failed with exit code ${exit_code}" >&2
    if [[ -n "$context" ]]; then
      echo "  on \"${context}\"" >&2
    fi
    echo "  of \"${cmd}\"" >&2
    if [[ -n "$stderr_content" ]]; then
      echo "  with error:" >&2
      echo "$stderr_content" | sed 's/^/    /' >&2
    fi
    exit "$exit_code"
  fi

  # If successful, still show stderr (warnings, etc.) but don't exit
  cat "$stderr_file" >&2
}

# ---- event dispatch (block-aware) ----
dispatch_event_handlers() {
  local hook="$1"
  shift || true
  local -a hook_args=("$@")

  local specific="" kind_generic="" universal="onEvent"

  if [[ "${FISHOOK_EVENT_KIND:-}" == "file" ]]; then
    kind_generic="onFileEvent"
    case "${FISHOOK_EVENT:-}" in
      add) specific="onAdd" ;;
      change) specific="onChange" ;;
      delete) specific="onDelete" ;;
      move) specific="onMove" ;;
      copy) specific="onCopy" ;;
    esac
  elif [[ "${FISHOOK_EVENT_KIND:-}" == "ref" ]]; then
    kind_generic="onRefEvent"
    case "${FISHOOK_EVENT:-}" in
      ref_create) specific="onRefCreate" ;;
      ref_update) specific="onRefUpdate" ;;
      ref_delete) specific="onRefDelete" ;;
    esac
  fi

  local blocks_json block
  blocks_json="$(hook_blocks_json "$hook")"
  [[ "$blocks_json" == "[]" ]] && return 0

  # Iterate blocks
  while IFS= read -r block; do
    # Apply file filters if applicable
    if [[ "${FISHOOK_EVENT_KIND:-}" == "file" ]]; then
      local p
      p="$(fishook_primary_path)"

      # Check if file is within config directory scope (if FISHOOK_CONFIG_DIR is set)
      if [[ -n "${FISHOOK_CONFIG_DIR:-}" ]]; then
        local abs_p
        abs_p="$(abs_in_repo "$p")"
        # Check if file path starts with config directory path
        if [[ "$abs_p" != "$FISHOOK_CONFIG_DIR"* ]]; then
          continue
        fi
      fi

      local apply_json skip_json
      apply_json="$(block_apply_to_json "$block")"
      skip_json="$(block_skip_list_json "$block")"

      local -a apply=() skip=()
      mapfile -t apply < <(printf '%s' "$apply_json" | jq -r '.[]')
      mapfile -t skip  < <(printf '%s' "$skip_json"  | jq -r '.[]')

      if ! fishook_block_allows_path "$p" "${apply[@]}" -- "${skip[@]}"; then
        continue
      fi
    fi

    # Run handlers in order: specific -> kind_generic -> universal
    local key cmds_json cmd
    for key in "$specific" "$kind_generic" "$universal"; do
      [[ -z "$key" ]] && continue
      cmds_json="$(block_key_cmds_json "$block" "$key")"
      [[ "$cmds_json" == "[]" ]] && continue
      while IFS= read -r cmd; do
        run_one_cmd "$hook" "$cmd" "$key" "${hook_args[@]}"
      done < <(printf '%s' "$cmds_json" | jq -r '.[]')
    done
  done < <(printf '%s' "$blocks_json" | jq -c '.[]') # stable line-per-block
}

# ---- event emitters ----
emit_file_events_from_name_status_z() {
  local hook="$1"
  local old_oid="${2:-}"
  local new_oid="${3:-}"
  shift 3 || true
  local -a hook_args=("$@")

  # input is: status\0path\0  OR  Rxxx\0src\0dst\0, Cxxx\0src\0dst\0
  while IFS= read -r -d '' status; do
    case "$status" in
      A|M|D)
        IFS= read -r -d '' path || true
        clear_event_env
        export FISHOOK_EVENT_KIND="file"
        export FISHOOK_STATUS="$status"
        export FISHOOK_PATH="$path"
        export FISHOOK_ABS_PATH="$(abs_in_repo "$path")"
        [[ -n "$old_oid" ]] && export FISHOOK_OLD_OID="$old_oid" || true
        [[ -n "$new_oid" ]] && export FISHOOK_NEW_OID="$new_oid" || true
        case "$status" in
          A) export FISHOOK_EVENT="add" ;;
          M) export FISHOOK_EVENT="change" ;;
          D) export FISHOOK_EVENT="delete" ;;
        esac
        dispatch_event_handlers "$hook" "${hook_args[@]}"
        ;;
      R*|C*)
        IFS= read -r -d '' src || true
        IFS= read -r -d '' dst || true
        clear_event_env
        export FISHOOK_EVENT_KIND="file"
        export FISHOOK_STATUS="$status"
        export FISHOOK_SRC="$src"
        export FISHOOK_DST="$dst"
        export FISHOOK_ABS_SRC="$(abs_in_repo "$src")"
        export FISHOOK_ABS_DST="$(abs_in_repo "$dst")"
        [[ -n "$old_oid" ]] && export FISHOOK_OLD_OID="$old_oid" || true
        [[ -n "$new_oid" ]] && export FISHOOK_NEW_OID="$new_oid" || true
        case "$status" in
          R*) export FISHOOK_EVENT="move" ;;
          C*) export FISHOOK_EVENT="copy" ;;
        esac
        dispatch_event_handlers "$hook" "${hook_args[@]}"
        ;;
      *)
        :
        ;;
    esac
  done
}

emit_pre_commit_file_events() {
  local hook="$1"; shift || true
  local -a hook_args=("$@")
  # old/new unset => diff() falls back to --cached
  git diff --cached --name-status -z | emit_file_events_from_name_status_z "$hook" "" "" "${hook_args[@]}"
}

emit_diff_tree_file_events() {
  local hook="$1"
  local old="$2"
  local new="$3"
  shift 3 || true
  local -a hook_args=("$@")

  git cat-file -e "${old}^{commit}" >/dev/null 2>&1 || return 0
  git cat-file -e "${new}^{commit}" >/dev/null 2>&1 || return 0

  git diff-tree -r --name-status -z "$old" "$new" | emit_file_events_from_name_status_z "$hook" "$old" "$new" "${hook_args[@]}"
}

emit_post_checkout_file_events() {
  local hook="$1"; shift || true
  local -a hook_args=("$@")
  local old="${hook_args[0]:-}"
  local new="${hook_args[1]:-}"
  [[ -n "$old" && -n "$new" ]] || return 0
  emit_diff_tree_file_events "$hook" "$old" "$new" "${hook_args[@]}"
}

emit_post_merge_file_events() {
  local hook="$1"; shift || true
  local -a hook_args=("$@")
  local old new
  old="$(git rev-parse -q --verify ORIG_HEAD 2>/dev/null || true)"
  new="$(git rev-parse -q --verify HEAD 2>/dev/null || true)"
  [[ -n "$old" && -n "$new" ]] || return 0
  emit_diff_tree_file_events "$hook" "$old" "$new" "${hook_args[@]}"
}

emit_ref_events_pre_push() {
  local hook="$1"; shift || true
  local -a hook_args=("$@")
  local remote_name="${hook_args[0]:-}"
  local remote_url="${hook_args[1]:-}"

  while read -r local_ref local_oid remote_ref remote_oid; do
    [[ -z "${local_ref:-}" ]] && continue
    clear_event_env
    export FISHOOK_EVENT_KIND="ref"
    export FISHOOK_REMOTE_NAME="$remote_name"
    export FISHOOK_REMOTE_URL="$remote_url"
    export FISHOOK_REF="$remote_ref"
    export FISHOOK_OLD_OID="$remote_oid"
    export FISHOOK_NEW_OID="$local_oid"

    if [[ "${remote_oid:-}" =~ ^0+$ ]]; then
      export FISHOOK_EVENT="ref_create"
    elif [[ "${local_oid:-}" =~ ^0+$ ]]; then
      export FISHOOK_EVENT="ref_delete"
    else
      export FISHOOK_EVENT="ref_update"
    fi

    dispatch_event_handlers "$hook" "${hook_args[@]}"
  done
}

emit_ref_events_receive_pack_stdin() {
  local hook="$1"; shift || true
  local -a hook_args=("$@")
  while read -r old_oid new_oid ref; do
    [[ -z "${ref:-}" ]] && continue
    clear_event_env
    export FISHOOK_EVENT_KIND="ref"
    export FISHOOK_REF="$ref"
    export FISHOOK_OLD_OID="$old_oid"
    export FISHOOK_NEW_OID="$new_oid"

    if [[ "${old_oid:-}" =~ ^0+$ ]]; then
      export FISHOOK_EVENT="ref_create"
    elif [[ "${new_oid:-}" =~ ^0+$ ]]; then
      export FISHOOK_EVENT="ref_delete"
    else
      export FISHOOK_EVENT="ref_update"
    fi

    dispatch_event_handlers "$hook" "${hook_args[@]}"
  done
}

emit_ref_event_update_args() {
  local hook="$1"; shift || true
  local -a hook_args=("$@")
  local ref="${hook_args[0]:-}"
  local old_oid="${hook_args[1]:-}"
  local new_oid="${hook_args[2]:-}"
  [[ -n "$ref" && -n "$old_oid" && -n "$new_oid" ]] || return 0

  clear_event_env
  export FISHOOK_EVENT_KIND="ref"
  export FISHOOK_REF="$ref"
  export FISHOOK_OLD_OID="$old_oid"
  export FISHOOK_NEW_OID="$new_oid"

  if [[ "$old_oid" =~ ^0+$ ]]; then
    export FISHOOK_EVENT="ref_create"
  elif [[ "$new_oid" =~ ^0+$ ]]; then
    export FISHOOK_EVENT="ref_delete"
  else
    export FISHOOK_EVENT="ref_update"
  fi

  dispatch_event_handlers "$hook" "${hook_args[@]}"
}

# ---- commands ----
do_list() {
  echo "Client-side (patch / email workflows)"
  local h
  for h in applypatch-msg pre-applypatch post-applypatch sendemail-validate; do
    printf "  %-18s %s\n" "$h" "$(hook_explain_text "$h")"
  done
  echo

  echo "Client-side (commit workflow)"
  for h in pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit; do
    printf "  %-18s %s\n" "$h" "$(hook_explain_text "$h")"
  done
  echo

  echo "Client-side (branch / history changes)"
  for h in pre-rebase post-checkout post-merge post-rewrite; do
    printf "  %-18s %s\n" "$h" "$(hook_explain_text "$h")"
  done
  echo

  echo "Client-side (push / maintenance)"
  for h in pre-push pre-auto-gc; do
    printf "  %-18s %s\n" "$h" "$(hook_explain_text "$h")"
  done
  echo

  echo "Server-side (bare repo / self-hosted only; not GitHub/GitLab.com)"
  for h in pre-receive update post-receive post-update push-to-checkout proc-receive; do
    printf "  %-18s %s\n" "$h" "$(hook_explain_text "$h")"
  done
  echo

  echo "Performance"
  for h in fsmonitor-watchman; do
    printf "  %-18s %s\n" "$h" "$(hook_explain_text "$h")"
  done
}

do_list_simple() {
  local h
  for h in applypatch-msg pre-applypatch post-applypatch sendemail-validate; do
    printf "$h"
  done
  for h in pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit; do
    printf "$h"
  done
  for h in pre-rebase post-checkout post-merge post-rewrite; do
    printf "$h"
  done
  for h in pre-push pre-auto-gc; do
    printf "$h"
  done
  for h in pre-receive update post-receive post-update push-to-checkout proc-receive; do
    printf "$h"
  done
  for h in fsmonitor-watchman; do
    printf "$h"
  done
}

do_scope() {
  cat <<'EOF'
fishook scope - Available environment variables and functions

ENVIRONMENT VARIABLES:

Base variables (always available):
  FISHOOK_HOOK             Current hook name (e.g., "pre-commit", "pre-push")
  FISHOOK_REPO_ROOT        Absolute path to repository root
  FISHOOK_REPO_NAME        Repository name (basename of root)
  FISHOOK_GIT_DIR          Absolute path to .git directory
  FISHOOK_CONFIG_PATH      Path to fishook.json being used
  FISHOOK_CONFIG_DIR       Directory containing config (for scoped configs)
  FISHOOK_HOOKS_PATH       Path to .git/hooks directory
  FISHOOK_COMMON           Path to fishook's common/ helper scripts
  FISHOOK_DRY_RUN          "1" if --dry-run, "0" otherwise
  FISHOOK_CWD              Working directory when invoked
  FISHOOK_ARGV0            The $0 argument (hook script path)
  FISHOOK_ARGS             Space-separated, shell-quoted hook arguments

Event-specific variables (set during file/ref events):
  FISHOOK_EVENT_KIND       "file" or "ref"
  FISHOOK_EVENT            Event type:
                             file: add, change, delete, move, copy
                             ref: ref_create, ref_update, ref_delete
  FISHOOK_STATUS           Git status (A=add, M=modify, D=delete, R=rename, C=copy)

File event variables:
  FISHOOK_PATH             Relative file path (add/change/delete)
  FISHOOK_ABS_PATH         Absolute file path
  FISHOOK_SRC              Source path (move/copy)
  FISHOOK_DST              Destination path (move/copy)
  FISHOOK_ABS_SRC          Absolute source path
  FISHOOK_ABS_DST          Absolute destination path

Ref event variables:
  FISHOOK_REF              Ref being updated (e.g., "refs/heads/main")
  FISHOOK_OLD_OID          Old commit SHA (0000... for new refs)
  FISHOOK_NEW_OID          New commit SHA (0000... for deleted refs)
  FISHOOK_REMOTE_NAME      Remote name (pre-push only)
  FISHOOK_REMOTE_URL       Remote URL (pre-push only)

FUNCTIONS:

File content helpers:
  old                      Print old version of file (HEAD or FISHOOK_OLD_OID)
                           Example: old | grep pattern

  new                      Print new version of file (index/worktree or FISHOOK_NEW_OID)
                           Example: new | grep pattern

  diff                     Show git diff for current file
                           Example: diff | grep -q "TODO"

File modification:
  modify [flags] [text]    Modify current file in index and/or worktree
                           Flags:
                             --index-only, --staged-only
                             --worktree-only, --local-only
                             --no-stage
                           Example: new | sed 's/foo/bar/' | modify
                           Example: modify "new content"

  pcsed [flags] <expr>     Apply sed to current file (uses modify internally)
                           Example: pcsed 's/TODO/DONE/g'
                           Example: pcsed --index-only 's/v1/v2/'

Validation:
  raise <message>          Fail hook with error message
                           Example: raise "commit message too short"

  forbid_pattern           Fail if content matches regex
    <pattern> [message]    Example: forbid_pattern 'console\.log' "no console.log"

  forbid_file_pattern      Fail if filename matches regex
    <pattern> [message]    Example: forbid_file_pattern '\.orig$' "no .orig files"

Utilities:
  ensure_executable        Make file executable (chmod +x and git add)
    [path]                 Example: ensure_executable scripts/deploy.sh

  modify_commit_message    Modify commit message with sed
    <file> <sed-expr>      Example: modify_commit_message "$1" 's/^/[TAG] /'

  iter_source <dir>        Source all .sh files in directory
                           Example: iter_source "$FISHOOK_COMMON/plugins"

  fishook_old_path         Print "old" path (FISHOOK_SRC or FISHOOK_PATH)
  fishook_new_path         Print "new" path (FISHOOK_DST or FISHOOK_PATH)

Run 'fishook explain <hook-name>' to see configured actions for a specific hook.
EOF
}

# ---- explain helpers for variables, functions, and commands ----
explain_variable() {
  local var="$1"
  case "$var" in
    FISHOOK_HOOK)
      cat <<'EOF'
FISHOOK_HOOK

The current hook name being executed (e.g., "pre-commit", "pre-push", "commit-msg").

Type: string
Always available: yes
Example values: "pre-commit", "post-checkout", "pre-push"

Usage:
  echo "Running hook: $FISHOOK_HOOK"
  if [[ "$FISHOOK_HOOK" == "pre-commit" ]]; then
    echo "Pre-commit checks..."
  fi
EOF
      ;;
    FISHOOK_REPO_ROOT)
      cat <<'EOF'
FISHOOK_REPO_ROOT

Absolute path to the repository root directory.

Type: string (absolute path)
Always available: yes
Example: "/home/user/projects/my-repo"

Usage:
  cd "$FISHOOK_REPO_ROOT"
  cat "$FISHOOK_REPO_ROOT/package.json"
EOF
      ;;
    FISHOOK_REPO_NAME)
      cat <<'EOF'
FISHOOK_REPO_NAME

Name of the repository (basename of the repository root directory).

Type: string
Always available: yes
Example: "my-repo"

Usage:
  echo "Repository: $FISHOOK_REPO_NAME"
EOF
      ;;
    FISHOOK_GIT_DIR)
      cat <<'EOF'
FISHOOK_GIT_DIR

Absolute path to the .git directory.

Type: string (absolute path)
Always available: yes
Example: "/home/user/projects/my-repo/.git"

Usage:
  cat "$FISHOOK_GIT_DIR/config"
EOF
      ;;
    FISHOOK_CONFIG_PATH)
      cat <<'EOF'
FISHOOK_CONFIG_PATH

Path to the fishook.json config file being used.

Type: string (absolute path)
Always available: yes
Example: "/home/user/projects/my-repo/fishook.json"

Usage:
  echo "Using config: $FISHOOK_CONFIG_PATH"
EOF
      ;;
    FISHOOK_CONFIG_DIR)
      cat <<'EOF'
FISHOOK_CONFIG_DIR

Directory containing the fishook.json config file. Used for scoped configs
to determine which files the config should apply to.

Type: string (absolute path)
Available: when using scoped/nested configs
Example: "/home/user/projects/my-repo/subdir"

Usage:
  echo "Config scope: $FISHOOK_CONFIG_DIR"
EOF
      ;;
    FISHOOK_HOOKS_PATH)
      cat <<'EOF'
FISHOOK_HOOKS_PATH

Path to the .git/hooks directory.

Type: string (absolute path)
Always available: yes
Example: "/home/user/projects/my-repo/.git/hooks"

Usage:
  ls "$FISHOOK_HOOKS_PATH"
EOF
      ;;
    FISHOOK_COMMON)
      cat <<'EOF'
FISHOOK_COMMON

Path to fishook's common/ directory containing helper scripts.

Type: string (absolute path)
Always available: yes
Example: "/usr/local/lib/node_modules/fishook/common"

Usage:
  source "$FISHOOK_COMMON/custom-helpers.sh"
  ls "$FISHOOK_COMMON"
EOF
      ;;
    FISHOOK_DRY_RUN)
      cat <<'EOF'
FISHOOK_DRY_RUN

Indicates whether --dry-run mode is active. "1" if dry-run, "0" otherwise.

Type: string ("0" or "1")
Always available: yes

Usage:
  if [[ "$FISHOOK_DRY_RUN" == "1" ]]; then
    echo "Would execute command (dry run)"
  else
    execute_command
  fi
EOF
      ;;
    FISHOOK_CWD)
      cat <<'EOF'
FISHOOK_CWD

Working directory when fishook was invoked.

Type: string (absolute path)
Always available: yes
Example: "/home/user/projects/my-repo/subdirectory"

Usage:
  cd "$FISHOOK_CWD"
EOF
      ;;
    FISHOOK_ARGV0)
      cat <<'EOF'
FISHOOK_ARGV0

The $0 argument (path to the hook script being executed).

Type: string
Always available: yes
Example: ".git/hooks/pre-commit"

Usage:
  echo "Hook script: $FISHOOK_ARGV0"
EOF
      ;;
    FISHOOK_ARGS)
      cat <<'EOF'
FISHOOK_ARGS

Space-separated, shell-quoted hook arguments passed to the hook.

Type: string
Always available: yes
Example: "origin https://github.com/user/repo.git"

Usage:
  echo "Hook arguments: $FISHOOK_ARGS"
EOF
      ;;
    FISHOOK_EVENT_KIND)
      cat <<'EOF'
FISHOOK_EVENT_KIND

Type of event being processed: "file" or "ref".

Type: string
Available: during event handlers (onFileEvent, onRefEvent, etc.)
Values: "file" | "ref"

Usage:
  if [[ "$FISHOOK_EVENT_KIND" == "file" ]]; then
    echo "Processing file event"
  fi
EOF
      ;;
    FISHOOK_EVENT)
      cat <<'EOF'
FISHOOK_EVENT

Specific event type being processed.

Type: string
Available: during event handlers
File events: "add", "change", "delete", "move", "copy"
Ref events: "ref_create", "ref_update", "ref_delete"

Usage:
  case "$FISHOOK_EVENT" in
    add) echo "New file: $FISHOOK_PATH" ;;
    change) echo "Modified: $FISHOOK_PATH" ;;
    delete) echo "Deleted: $FISHOOK_PATH" ;;
  esac
EOF
      ;;
    FISHOOK_STATUS)
      cat <<'EOF'
FISHOOK_STATUS

Git status letter indicating the type of change.

Type: string
Available: during file events
Values: "A" (add), "M" (modify), "D" (delete), "R"* (rename), "C"* (copy)

Usage:
  echo "Status: $FISHOOK_STATUS"
EOF
      ;;
    FISHOOK_PATH)
      cat <<'EOF'
FISHOOK_PATH

Relative path to the file being processed (for add/change/delete events).

Type: string (relative path)
Available: during file events (add, change, delete)
Example: "src/main.js"

Usage:
  echo "File: $FISHOOK_PATH"
  if [[ "$FISHOOK_PATH" == *.js ]]; then
    eslint "$FISHOOK_PATH"
  fi
EOF
      ;;
    FISHOOK_ABS_PATH)
      cat <<'EOF'
FISHOOK_ABS_PATH

Absolute path to the file being processed.

Type: string (absolute path)
Available: during file events (add, change, delete)
Example: "/home/user/projects/my-repo/src/main.js"

Usage:
  cat "$FISHOOK_ABS_PATH"
EOF
      ;;
    FISHOOK_SRC)
      cat <<'EOF'
FISHOOK_SRC

Source path for move/copy events (relative).

Type: string (relative path)
Available: during move/copy file events
Example: "old-name.js"

Usage:
  echo "Moved from: $FISHOOK_SRC to $FISHOOK_DST"
EOF
      ;;
    FISHOOK_DST)
      cat <<'EOF'
FISHOOK_DST

Destination path for move/copy events (relative).

Type: string (relative path)
Available: during move/copy file events
Example: "new-name.js"

Usage:
  echo "Moved to: $FISHOOK_DST"
EOF
      ;;
    FISHOOK_ABS_SRC)
      cat <<'EOF'
FISHOOK_ABS_SRC

Absolute source path for move/copy events.

Type: string (absolute path)
Available: during move/copy file events
Example: "/home/user/projects/my-repo/old-name.js"
EOF
      ;;
    FISHOOK_ABS_DST)
      cat <<'EOF'
FISHOOK_ABS_DST

Absolute destination path for move/copy events.

Type: string (absolute path)
Available: during move/copy file events
Example: "/home/user/projects/my-repo/new-name.js"
EOF
      ;;
    FISHOOK_REF)
      cat <<'EOF'
FISHOOK_REF

The ref being updated (e.g., branch or tag name).

Type: string
Available: during ref events (pre-push, pre-receive, update, etc.)
Example: "refs/heads/main", "refs/tags/v1.0.0"

Usage:
  if [[ "$FISHOOK_REF" == refs/heads/main ]]; then
    echo "Updating main branch"
  fi
EOF
      ;;
    FISHOOK_OLD_OID)
      cat <<'EOF'
FISHOOK_OLD_OID

Old commit SHA before the change (or all zeros for new refs).

Type: string (40-character hex SHA or zeros)
Available: during ref events and some file events
Example: "abc123...", "0000000000000000000000000000000000000000"

Usage:
  if [[ "$FISHOOK_OLD_OID" =~ ^0+$ ]]; then
    echo "New ref"
  fi
EOF
      ;;
    FISHOOK_NEW_OID)
      cat <<'EOF'
FISHOOK_NEW_OID

New commit SHA after the change (or all zeros for deleted refs).

Type: string (40-character hex SHA or zeros)
Available: during ref events and some file events
Example: "def456...", "0000000000000000000000000000000000000000"

Usage:
  if [[ "$FISHOOK_NEW_OID" =~ ^0+$ ]]; then
    echo "Deleted ref"
  fi
EOF
      ;;
    FISHOOK_REMOTE_NAME)
      cat <<'EOF'
FISHOOK_REMOTE_NAME

Remote name for push operations.

Type: string
Available: pre-push hook only
Example: "origin"

Usage:
  echo "Pushing to remote: $FISHOOK_REMOTE_NAME"
EOF
      ;;
    FISHOOK_REMOTE_URL)
      cat <<'EOF'
FISHOOK_REMOTE_URL

Remote URL for push operations.

Type: string
Available: pre-push hook only
Example: "https://github.com/user/repo.git"

Usage:
  echo "Remote URL: $FISHOOK_REMOTE_URL"
EOF
      ;;
    GIT_HOOK_KEY|GIT_HOOK_ARGS)
      cat <<'EOF'
GIT_HOOK_KEY / GIT_HOOK_ARGS

Legacy variables for backwards compatibility.
Use FISHOOK_HOOK and FISHOOK_ARGS instead.

Status: deprecated
EOF
      ;;
    *)
      echo "Unknown variable: $var"
      echo "Run 'fishook scope' to see all available variables."
      return 1
      ;;
  esac
}

explain_function() {
  local func="$1"
  case "$func" in
    old)
      cat <<'EOF'
old()

Print the old version of the current file (from HEAD or FISHOOK_OLD_OID).

Usage: old
Output: file contents to stdout

Available: during file events with FISHOOK_PATH set
Returns: 0 on success

Examples:
  old | grep pattern
  old > old-version.txt
  if old | grep -q "TODO"; then
    raise "TODO found in old version"
  fi

See also: new, diff
EOF
      ;;
    new)
      cat <<'EOF'
new()

Print the new version of the current file (from index/worktree or FISHOOK_NEW_OID).

Usage: new
Output: file contents to stdout

Available: during file events with FISHOOK_PATH set
Returns: 0 on success

Examples:
  new | grep pattern
  new > new-version.txt
  if new | grep -q "console.log"; then
    raise "console.log found"
  fi

See also: old, diff
EOF
      ;;
    diff)
      cat <<'EOF'
diff()

Show the git diff for the current file.

Usage: diff
Output: git diff output to stdout

Available: during file events with FISHOOK_PATH set
Returns: 0 on success

Examples:
  diff | grep -q "TODO"
  diff > changes.patch
  if diff | grep -q "+.*password"; then
    raise "Password added to file"
  fi

See also: old, new
EOF
      ;;
    modify)
      cat <<'EOF'
modify([flags] [text])

Modify the current file in index and/or worktree.

Usage: modify [--index-only|--worktree-only|--no-stage] [text]

Flags:
  --index-only, --staged-only      Only update the staged version
  --worktree-only, --local-only    Update worktree and stage it
  --no-stage                       Update worktree but don't stage

Input: Reads from stdin if no text argument provided
Available: during file events with FISHOOK_PATH set
Returns: 0 on success

Examples:
  new | sed 's/foo/bar/' | modify
  modify "new content here"
  new | tr '[:lower:]' '[:upper:]' | modify --index-only
  echo "# Header" | modify --no-stage

See also: pcsed, new
EOF
      ;;
    pcsed)
      cat <<'EOF'
pcsed([modify-flags] sed-expr)

Apply sed transformation to current file (uses modify internally).

Usage: pcsed [modify-flags] <sed-expression>

Flags: same as modify (--index-only, --worktree-only, --no-stage)
Available: during file events with FISHOOK_PATH set
Returns: 0 on success, 2 on usage error

Examples:
  pcsed 's/TODO/DONE/g'
  pcsed --index-only 's/version = .*/version = 2.0/'
  pcsed 's/foo/bar/gi' --no-stage

Note: Uses sed -E (extended regex)
See also: modify, new
EOF
      ;;
    raise)
      cat <<'EOF'
raise(message)

Fail the hook with an error message and exit code 1.

Usage: raise <message>

Arguments:
  message    Error message to display

Output: Formatted error message to stderr
Exit: Always exits with code 1

Examples:
  raise "commit message too short"
  raise "TODO found in staged files"
  [[ -n "$FISHOOK_PATH" ]] || raise "FISHOOK_PATH not set"

See also: forbid_pattern, forbid_file_pattern
EOF
      ;;
    forbid_pattern)
      cat <<'EOF'
forbid_pattern(pattern [message])

Fail if file content matches regex pattern.

Usage: forbid_pattern <pattern> [message]

Arguments:
  pattern    Extended regex pattern to search for
  message    Optional error message (default: "contains forbidden pattern")

Available: during file events with FISHOOK_PATH set
Returns: 0 if pattern not found, exits 1 if found

Examples:
  forbid_pattern 'console\.log' "console.log not allowed"
  forbid_pattern '\bTODO\b'
  forbid_pattern 'password.*=' "Password hardcoded in file"

See also: forbid_file_pattern, raise, new
EOF
      ;;
    forbid_file_pattern)
      cat <<'EOF'
forbid_file_pattern(pattern [message])

Fail if filename matches regex pattern.

Usage: forbid_file_pattern <pattern> [message]

Arguments:
  pattern    Extended regex pattern to match filename against
  message    Optional error message (default: "file name matches forbidden pattern")

Available: during file events with FISHOOK_PATH set
Returns: 0 if pattern doesn't match, exits 1 if matches

Examples:
  forbid_file_pattern '\.orig$' "merge conflict files not allowed"
  forbid_file_pattern '^\.env' ".env files should not be committed"
  forbid_file_pattern 'test-.*\.skip\.js' "Skipped test files not allowed"

See also: forbid_pattern, raise
EOF
      ;;
    ensure_executable)
      cat <<'EOF'
ensure_executable([path])

Make file executable if it isn't already (chmod +x and git add).

Usage: ensure_executable [path]

Arguments:
  path    Optional file path (defaults to FISHOOK_PATH)

Available: during file events or with explicit path
Returns: 0 on success, 1 on error

Examples:
  ensure_executable
  ensure_executable scripts/deploy.sh
  ensure_executable "$FISHOOK_DST"

Note: Automatically stages the change
EOF
      ;;
    modify_commit_message)
      cat <<'EOF'
modify_commit_message(file sed-expr)

Modify a commit message file with sed.

Usage: modify_commit_message <file> <sed-expression>

Arguments:
  file        Path to commit message file (usually $1 in commit-msg hook)
  sed-expr    Sed expression to apply

Available: commit-msg, prepare-commit-msg hooks
Returns: 0 on success

Examples:
  modify_commit_message "$1" 's/^/[PREFIX] /'
  modify_commit_message "$1" '1s/^/JIRA-123: /'
  modify_commit_message "$1" '/^#/d'

Note: Modifies file in-place with sed -i
EOF
      ;;
    iter_source)
      cat <<'EOF'
iter_source(directory)

Source all .sh files in a directory.

Usage: iter_source <directory>

Arguments:
  directory    Path to directory containing .sh files

Returns: 0 on success, 1 if directory doesn't exist

Examples:
  iter_source "$FISHOOK_COMMON/plugins"
  iter_source "$FISHOOK_REPO_ROOT/hooks/helpers"

Use case: Load custom helper functions from a directory
EOF
      ;;
    fishook_old_path)
      cat <<'EOF'
fishook_old_path()

Print the "old" path (FISHOOK_SRC or FISHOOK_PATH).

Usage: fishook_old_path
Output: path string to stdout

Available: during file events
Returns: 0 always

Example:
  path=$(fishook_old_path)
  echo "Old path: $path"

See also: fishook_new_path, old
EOF
      ;;
    fishook_new_path)
      cat <<'EOF'
fishook_new_path()

Print the "new" path (FISHOOK_DST or FISHOOK_PATH).

Usage: fishook_new_path
Output: path string to stdout

Available: during file events
Returns: 0 always

Example:
  path=$(fishook_new_path)
  echo "New path: $path"

See also: fishook_old_path, new
EOF
      ;;
    *)
      echo "Unknown function: $func"
      echo "Run 'fishook scope' to see all available functions."
      return 1
      ;;
  esac
}

explain_command() {
  local cmd="$1"
  case "$cmd" in
    install)
      cat <<'EOF'
fishook install

Install fishook stubs into .git/hooks directory.

Usage: fishook install [--config /path/to/fishook.json] [--hooks-path PATH]

Options:
  --config PATH       Use specific config file (default: <repo-root>/fishook.json)
  --hooks-path PATH   Install to specific hooks directory (default: .git/hooks)

Behavior:
  - Creates a sample fishook.json if it doesn't exist
  - Installs stub scripts for all standard git hooks
  - Prompts for existing hooks (overwrite/chain/backup)
  - Writes hooks that call: fishook <hook-name> "$@"

Environment variable for automation:
  FISHOOK_INSTALL_CHOICE=1|2|3    Non-interactive choice:
    1 = overwrite
    2 = chain (preserve existing hook)
    3 = backup

Examples:
  fishook install
  fishook install --config custom-hooks.json
  FISHOOK_INSTALL_CHOICE=2 fishook install
EOF
      ;;
    uninstall)
      cat <<'EOF'
fishook uninstall

Remove fishook stubs from .git/hooks directory.

Usage: fishook uninstall [--hooks-path PATH]

Options:
  --hooks-path PATH   Uninstall from specific hooks directory (default: .git/hooks)

Behavior:
  - Removes all fishook-managed hook stubs
  - Restores chained hooks from .fishook-prev files
  - Removes fishook.json config file

Examples:
  fishook uninstall
  fishook uninstall --hooks-path /path/to/hooks
EOF
      ;;
    list)
      cat <<'EOF'
fishook list

List all available git hooks with descriptions.

Usage: fishook list

Output: Categorized list of hooks with explanations

Categories:
  - Client-side (patch/email workflows)
  - Client-side (commit workflow)
  - Client-side (branch/history changes)
  - Client-side (push/maintenance)
  - Server-side (bare repo only)
  - Performance

Example:
  fishook list
EOF
      ;;
    scope)
      cat <<'EOF'
fishook scope

Show all available environment variables and functions.

Usage: fishook scope

Output: Complete reference of:
  - Base variables (always available)
  - Event-specific variables (file/ref events)
  - File content helper functions
  - File modification functions
  - Validation functions
  - Utility functions

Example:
  fishook scope
  fishook scope | less
EOF
      ;;
    help|explain)
      cat <<'EOF'
fishook help / fishook explain

Get detailed help on hooks, variables, functions, or commands.

Usage:
  fishook help                            Show general usage
  fishook help <hook-name>                Explain specific hook
  fishook help <variable-name>            Explain variable (e.g., FISHOOK_PATH)
  fishook help <function-name>            Explain function (e.g., new, modify)
  fishook help <command>                  Explain command (e.g., install)

Examples:
  fishook help pre-commit
  fishook help FISHOOK_PATH
  fishook help modify
  fishook help install

Note: 'fishook explain' is an alias for 'fishook help'
EOF
      ;;
    *)
      echo "Unknown command: $cmd"
      echo ""
      echo "Available commands: install, uninstall, list, scope, help"
      return 1
      ;;
  esac
}

do_explain() {
  local -a args=()
  mapfile -d '' -t args < <(parse_flags "$@")

  local topic="${args[0]:-}"
  [[ -n "$topic" ]] || die "usage: fishook explain <hook-name|variable|function|command>"

  # Check if it's a built-in command
  case "$topic" in
    install|uninstall|list|scope|help|explain)
      explain_command "$topic"
      return 0
      ;;
  esac

  # Check if it's a variable (starts with FISHOOK_ or GIT_HOOK_)
  if [[ "$topic" == FISHOOK_* || "$topic" == GIT_HOOK_* ]]; then
    explain_variable "$topic"
    return 0
  fi

  # Check if it's a known function
  case "$topic" in
    old|new|diff|modify|pcsed|raise|forbid_pattern|forbid_file_pattern|ensure_executable|modify_commit_message|iter_source|fishook_old_path|fishook_new_path)
      explain_function "$topic"
      return 0
      ;;
  esac

  # Check if it's a known hook
  if hook_known "$topic"; then
    require_jq
    in_git_repo || die "not inside a git repository"

    [[ -n "$CONFIG_PATH" ]] || CONFIG_PATH="$(default_config_path)"
    [[ -n "$HOOKS_PATH" ]] || HOOKS_PATH="$(default_hooks_path)"

    echo "$topic"
    echo "  $(hook_explain_text "$topic")"
    echo

    hook_scope_details "$topic"
    echo

    if [[ ! -f "$CONFIG_PATH" ]]; then
      echo "fishook.json: (missing) ${CONFIG_PATH}"
      return 0
    fi

    echo "Configured actions in ${CONFIG_PATH}:"
    echo

    local run_json
    run_json="$(hook_run_cmds_json "$topic")"
    if [[ "$run_json" == "[]" ]]; then
      echo "  run: (none)"
    else
      echo "  run:"
      printf '%s\n' "$run_json" | jq -r '.[]' | sed 's/^/    - /'
    fi

    local blocks_json
    blocks_json="$(hook_blocks_json "$topic")"
    if [[ "$blocks_json" != "[]" ]]; then
      echo
      echo "  blocks/handlers:"
      local idx=0
      while IFS= read -r block; do
        idx=$((idx + 1))
        local apply_json skip_json
        apply_json="$(block_apply_to_json "$block")"
        skip_json="$(block_skip_list_json "$block")"
        echo "    block #$idx:"
        if [[ "$apply_json" != "[]" ]]; then
          echo "      applyTo:"
          printf '%s\n' "$apply_json" | jq -r '.[]' | sed 's/^/        - /'
        fi
        if [[ "$skip_json" != "[]" ]]; then
          echo "      skipList:"
          printf '%s\n' "$skip_json" | jq -r '.[]' | sed 's/^/        - /'
        fi
        local keys=(
          onAdd onChange onDelete onMove onCopy onFileEvent
          onRefCreate onRefUpdate onRefDelete onRefEvent
          onEvent
        )
        local any=0 k kjson
        for k in "${keys[@]}"; do
          kjson="$(block_key_cmds_json "$block" "$k")"
          [[ "$kjson" == "[]" ]] && continue
          [[ $any -eq 0 ]] && any=1
          echo "      ${k}:"
          printf '%s\n' "$kjson" | jq -r '.[]' | sed 's/^/        - /'
        done
        [[ $any -eq 0 ]] && echo "      (no handlers)"
      done < <(printf '%s' "$blocks_json" | jq -c '.[]')
    fi
    return 0
  fi

  # Not found
  echo "Unknown topic: $topic"
  echo ""
  echo "Usage: fishook explain <topic>"
  echo ""
  echo "Topics can be:"
  echo "  - Hook names: pre-commit, commit-msg, pre-push, etc."
  echo "  - Variables: FISHOOK_PATH, FISHOOK_HOOK, etc."
  echo "  - Functions: new, old, modify, raise, etc."
  echo "  - Commands: install, uninstall, list, scope"
  echo ""
  echo "Run 'fishook list' to see all hooks"
  echo "Run 'fishook scope' to see all variables and functions"
  return 1
}

do_install() {
  require_jq
  in_git_repo || die "not inside a git repository"

  local -a _ignored=()
  mapfile -d '' -t _ignored < <(parse_flags "$@")

  [[ -n "$HOOKS_PATH" ]] || HOOKS_PATH="$(default_hooks_path)"
  mkdir -p "$HOOKS_PATH"

  [[ -n "$CONFIG_PATH" ]] || CONFIG_PATH="$(default_config_path)"
  write_sample_config "$CONFIG_PATH"

  local hook file prev bak choice
  for hook in "${ALL_HOOKS[@]}"; do
    file="${HOOKS_PATH}/${hook}"

    if [[ ! -e "$file" ]]; then
      write_stub "$hook" "$file"
      continue
    fi

    if is_fishook_stub "$file"; then
      continue
    fi

    choice="$(prompt_choice "$hook" "$file")"
    case "$choice" in
      1)
        bak="${file}.bak.$(timestamp)"
        mv "$file" "$bak"
        write_stub "$hook" "$file"
        ;;
      2)
        prev="${file}.fishook-prev"
        if [[ -e "$prev" ]]; then
          mv "$prev" "${prev}.bak.$(timestamp)"
        fi
        mv "$file" "$prev"
        write_chained_stub "$hook" "$file" "$prev"
        ;;
      3)
        bak="${file}.bak.$(timestamp)"
        mv "$file" "$bak"
        write_stub "$hook" "$file"
        ;;
      *)
        die "invalid choice: $choice"
        ;;
    esac
  done

  echo "fishook: installed stubs into ${HOOKS_PATH}" >&2
}

do_uninstall() {
  in_git_repo || die "not inside a git repository"

  [[ -n "$CONFIG_PATH" ]] || CONFIG_PATH="$(default_config_path)"
  if [[ -e "$CONFIG_PATH" ]]; then
    rm "$CONFIG_PATH"
    echo "removed $CONFIG_PATH"
  fi

  local -a _ignored=()
  mapfile -d '' -t _ignored < <(parse_flags "$@")

  [[ -n "$HOOKS_PATH" ]] || HOOKS_PATH="$(default_hooks_path)"

  local hook file prev
  for hook in "${ALL_HOOKS[@]}"; do
    file="${HOOKS_PATH}/${hook}"
    prev="${file}.fishook-prev"

    if [[ -e "$file" ]] && is_fishook_stub "$file"; then
      rm -f "$file"
      if [[ -e "$prev" ]]; then
        mv "$prev" "$file"
        chmod +x "$file" || true
      fi
    fi
  done

  echo "fishook: uninstalled stubs from ${HOOKS_PATH}" >&2
}

run_hook_for_config() {
  local hook="$1"
  local config_file="$2"
  shift 2 || true
  local -a hook_args=("$@")

  # Temporarily set CONFIG_PATH for this config file
  local ORIGINAL_CONFIG_PATH="$CONFIG_PATH"
  export CONFIG_PATH="$config_file"
  export FISHOOK_CONFIG_PATH="$CONFIG_PATH"

  # Set config directory scope (files must be at this level or below)
  local config_dir
  config_dir="$(dirname "$config_file")"
  export FISHOOK_CONFIG_DIR="$config_dir"

  # Step 1: run "run" commands (legacy/simple + block .run concatenation)
  local run_json cmd
  run_json="$(hook_run_cmds_json "$hook")"
  if [[ "$run_json" != "[]" ]]; then
    while IFS= read -r cmd; do
      run_one_cmd "$hook" "$cmd" "run" "${hook_args[@]}"
    done < <(printf '%s' "$run_json" | jq -r '.[]')
  fi

  # Step 2: emit events and run handlers (block-aware). Safe no-op if no handlers present.
  if hook_entry_has_blocks "$hook"; then
    case "$hook" in
      pre-commit)
        emit_pre_commit_file_events "$hook" "${hook_args[@]}"
        ;;
      post-checkout)
        emit_post_checkout_file_events "$hook" "${hook_args[@]}"
        ;;
      post-merge)
        emit_post_merge_file_events "$hook" "${hook_args[@]}"
        ;;
      pre-push)
        emit_ref_events_pre_push "$hook" "${hook_args[@]}"
        ;;
      pre-receive|post-receive)
        emit_ref_events_receive_pack_stdin "$hook" "${hook_args[@]}"
        ;;
      update)
        emit_ref_event_update_args "$hook" "${hook_args[@]}"
        ;;
      *)
        :
        ;;
    esac
  fi

  # Restore original CONFIG_PATH
  export CONFIG_PATH="$ORIGINAL_CONFIG_PATH"
}

do_run_hook() {
  require_jq
  in_git_repo || die "not inside a git repository"

  local hook="$1"; shift || true
  hook_known "$hook" || die "unknown hook: $hook"

  # Check for --dry-run flag before parse_flags (which runs in subshell)
  for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && DRY_RUN=1
  done

  local -a args=()
  mapfile -d '' -t args < <(parse_flags "$@")
  local -a hook_args=("${args[@]}")

  [[ -n "$HOOKS_PATH" ]] || HOOKS_PATH="$(default_hooks_path)"

  export_base_env "$hook"
  export FISHOOK_ARGS="$(printf '%q ' "${hook_args[@]}" | sed 's/ $//')"

  # Back-compat env
  export GIT_HOOK_KEY="$hook"
  export GIT_HOOK_ARGS="$FISHOOK_ARGS"

  # Hook-specific env vars
  case "$hook" in
    post-checkout)
      [[ "${#hook_args[@]}" -ge 2 ]] && export FISHOOK_REF="${hook_args[1]}" || true
      ;;
    pre-push)
      [[ "${#hook_args[@]}" -ge 1 ]] && export FISHOOK_REMOTE_NAME="${hook_args[0]}" || true
      [[ "${#hook_args[@]}" -ge 2 ]] && export FISHOOK_REMOTE_URL="${hook_args[1]}" || true
      ;;
  esac

  # Process configs: if --config specified, use only that; otherwise find all *fishook*.json
  local -a config_files=()
  if [[ -n "$CONFIG_PATH" ]]; then
    # Single config specified via --config flag
    [[ -f "$CONFIG_PATH" ]] || die "config not found: ${CONFIG_PATH}"
    config_files=("$CONFIG_PATH")
  else
    # Multi-config mode: find all *fishook*.json files
    mapfile -t config_files < <(find_all_configs)

    # Fall back to default if no configs found
    if [[ "${#config_files[@]}" -eq 0 ]]; then
      local default_config
      default_config="$(default_config_path)"
      if [[ -f "$default_config" ]]; then
        config_files=("$default_config")
      fi
    fi
  fi

  # Run hook for each config file found
  local config_file
  for config_file in "${config_files[@]}"; do
    [[ -f "$config_file" ]] || continue
    run_hook_for_config "$hook" "$config_file" "${hook_args[@]}"
  done
}

print_usage() {
  cat >&1 <<EOF
fishook

Usage:
  fishook install                     [--config /path/to/fishook.json] [--hooks-path PATH]     # install all hooks
  fishook uninstall                   [--hooks-path PATH]                                      # uninstall all hooks
  fishook list                                                                                 # lists all hooks
  fishook scope                                                                                # show available environment variables and functions
  fishook help <hook-name>            [--config /path/to/fishook.json] [--hooks-path PATH]     # explain hook: args, env vars, configured actions
  fishook <hook-name>  [hook-args...] [--config /path/to/fishook.json] [--dry-run]             # run the hook

fishook.json:
  - Put a fishook.json in your repo (default: <repo-root>/fishook.json)
  - Keys are git hook names (e.g. "pre-commit", "commit-msg")
  - Values are:
      * "string command"
      * ["cmd1", "cmd2", ...]
      * {"run": "cmd"} or {"run": ["cmd1","cmd2"]}  ("commands" also works)
      * or object/array-of-objects with handlers + optional applyTo/skipList

Examples:
  fishook install
  fishook scope
  fishook help pre-commit
  fishook pre-commit --dry-run
  fishook commit-msg .git/COMMIT_EDITMSG
EOF
}

# ---- dispatch ----
CMD="${1:-}"
shift || true

case "${CMD}" in
  ""|help|-h|--help|explain)
    if [[ $# -gt 0 ]]; then
      if [[ "$1" == "scope" ]]; then
        do_scope
      else
        # fishook help <hook-name> -> run explain
        do_explain "$@"
      fi
    else
      print_usage
    fi
    exit 0
    ;;
  install)
    do_install "$@"
    ;;
  uninstall)
    do_uninstall "$@"
    ;;
  list)
    do_list
    ;;
  scope)
    do_scope
    ;;
  *)
    do_run_hook "$CMD" "$@"
    ;;
esac
