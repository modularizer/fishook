# fishook 🐟🪝

**Git hooks without a framework.**

`fishook` is a tiny, transparent Git hook runner driven by a single file: `fishook.json`.

Just **Git hooks → json config -> shell commands**.

---

## Why fishook?

> Keep it simple, dummy.

* **un-opinionated** - Fishook is not opinionated, it just runs bash commands and helps you with a few shortcuts.
* **simple** - It is one or two steps simpler than modifying `.git/hooks/`, not twenty or thirty.
* **framework agnostic** - Fishook is written in pure bash and doesn't care if you use Node, Ruby, Python, Go, etc. git is git
* **low-dependency** - just uses `bash`, `jq`, `git` and `sed`.

---

## Common use cases

* **security** - Prevent secrets from being committed
* **quality** - Run tests or lint before commit / push
* **safety** - Block direct pushes to protected branches
* **standardization** - Enforce commit message formats
* **automation** - Auto-generate commit messages or changelogs
* **structure** - Enforce file size, naming, or content rules

---

## Quickstart

```bash
npm install --save-dev fishook  # runs fishook install via postinstall
# or: pipx install fishook
# or: pip install fishook

fishook install                 # install all hooks
# fishook install pre-commit commit-msg
```

### Minimal `fishook.json`

```json
{
  "pre-commit": "npm test",
  "post-checkout": "echo Checked out: $FISHOOK_REF"
}
```

That’s it.

---

## How it works

* Fishook installs lightweight Git hook shims
* On each hook, it loads matching `*fishook*.json` files
* Commands are executed **as-written** using `bash`
* No background daemons, caches, or magic state

If you can write a shell command, you can write a fishook rule.

---

### Feature overview
* connect to ANY hook `git` exposes
* use `onFileEvent` to run a command per file changed
* use `applyTo` and `skipList` to apply your command to only specific files
* use `source` to setup your environment before running commands
* use helpers whcih are already in the shell scope, like `new`, `old`, `diff`, `modify` to see file changes and update files in the staging area
* use `raise` to fail the hook with a message
* use multiple `fishook.json` files to allow commiting some to your repo while keeping others private

---

## Multiple config files (team + personal + scoped)

Fishook automatically loads **all `*fishook*.json` files** in your repo (up to 4 levels deep), in alphabetical order.

### Common pattern

```
repo/
├── fishook.json            # team-wide rules (tracked)
├── .fishook.local.json     # personal rules (gitignored)
└── frontend/
    └── fishook.json        # only applies to frontend/
```

`.gitignore`

```
.fishook.local.json
```

This enables:

* Shared enforcement for teams
* Personal hooks without forking config
* Directory-scoped rules for monorepos

---

## From simple to powerful

### Simple

```json
{
  "pre-commit": ["npm test", "npm run lint"],
  "commit-msg": "./validate_commit.sh"
}
```

### File-aware and event-driven

```json
{
  "pre-commit": [
    {
      "applyTo": ["*.js", "*.ts"],
      "onChange": [
        "$FISHOOK_COMMON/forbid-pattern.sh 'console\\.log' 'Remove console.log'"
      ]
    }
  ]
}
```

Fishook lets you react to:

* file adds / changes / deletes
* ref updates
* branch creation
* commit message edits

All without leaving JSON + shell.

---

## Full Git hook coverage

Fishook supports **every Git hook**, including:

* Commit workflow: `pre-commit`, `commit-msg`, `prepare-commit-msg`, …
* Branch & history: `pre-rebase`, `post-checkout`, `post-merge`, …
* Push & refs: `pre-push`, `update`, `post-receive`, …
* Server-side hooks (self-hosted repos)

Most tools *focus* on pre-commit.
Fishook exposes **everything Git exposes**.

---

## CLI (optional)

```bash
fishook                  # help
fishook install          # install hooks
fishook list             # list supported hooks
fishook explain pre-commit
fishook pre-commit       # run hook manually
fishook uninstall
```

You rarely need the CLI after install.

---

## Built-in utilities

Fishook ships with reusable shell helpers in `$FISHOOK_COMMON/`:

* `forbid-pattern` – block secrets or forbidden strings
* `forbid-file-pattern` – block filenames (e.g. `.env`)
* `ensure-executable` – auto‑chmod scripts
* `modify_commit_message`
* `pcsed` – safely edit staged vs working tree files

These are optional — you can always write your own shell.

---

## Philosophy

Fishook is deliberately:

* **Minimal** – one file, no plugins
* **Explicit** – no hidden behavior
* **Hackable** – shell in, shell out
* **Git‑native** – hooks behave exactly as Git defines them

If you’ve ever thought *“why is this so complicated?”* when configuring Git hooks — fishook is for you.

---

## Reference (configuration + runtime)


This section is the complete reference for:

* environment variables available to hook commands
* the supported JSON shapes
* config discovery & precedence
* install options

---

### Config discovery & order

Fishook loads **all files matching `*fishook*.json`** found up to **4 directory levels** deep.

* Files are processed in **alphabetical order**.
* A config file located in a subdirectory is **directory-scoped**: file events only apply to files at that directory level or below.
* Top-level keys like `setup` and `source` run as normal regardless of scope.

---

### Supported JSON shapes

At the top level, `fishook.json` is a mapping from **hook name → action(s)**, plus optional shared setup keys.

#### Minimal

```json
{
  "pre-commit": "npm test"
}
```

#### Multiple commands

```json
{
  "pre-commit": ["npm test", "npm run lint"]
}
```

#### Action object

```json
{
  "pre-commit": {
    "run": "npm test"
  }
}
```

#### Multiple actions per hook

```json
{
  "pre-commit": [
    "npm test",
    { "applyTo": ["*.js"], "onChange": ["npm run lint"] }
  ]
}
```

---

### The big one: `onFileEvent`

`onFileEvent` is fishook’s most powerful feature.

It runs **once per file event** (add/change/delete/move/copy) and gives you a consistent per-file context via env vars like:

* `FISHOOK_EVENT`
* `FISHOOK_PATH`
* `FISHOOK_SRC` / `FISHOOK_DST`

This lets you write **policy checks** and **auto-fixes** that operate on *the exact files involved* in a commit, push, merge, checkout, etc.

#### When to use `onFileEvent`

* block secrets or forbidden patterns in changed files
* enforce naming rules (no `.env`, no `*.pem`, etc.)
* enforce size limits for newly added files
* enforce executable bits on scripts
* run targeted formatters *only on changed files*

#### Minimal example

```json
{
  "pre-commit": {
    "onFileEvent": [
      "$FISHOOK_COMMON/forbid-file-pattern.sh '\.env$' 'Do not commit .env files'",
      "$FISHOOK_COMMON/forbid-pattern.sh '(password|secret|api[_-]?key)\s*=' 'Potential secret detected' || true"
    ]
  }
}
```

#### Example: enforce script executability

```json
{
  "pre-commit": [
    {
      "applyTo": ["*.sh", "scripts/**"],
      "onFileEvent": ["$FISHOOK_COMMON/ensure-executable.sh"]
    }
  ]
}
```

#### `applyTo` / `skipList` with `onFileEvent`

`applyTo` and `skipList` filter **file-event commands** (`onAdd`, `onChange`, `onDelete`, `onMove`, `onCopy`, `onFileEvent`).

* If `applyTo` is omitted, it matches all paths.
* If `skipList` matches, the file event is ignored.

```json
{
  "pre-commit": {
    "applyTo": ["src/**/*.{js,ts,jsx,tsx}"],
    "skipList": ["dist/**", "vendor/**"],
    "onFileEvent": ["npm run lint -- $FISHOOK_PATH"]
  }
}
```

#### Notes

* `onAdd` / `onChange` / etc. are *event-specific* convenience forms.
* `onFileEvent` is the **generic catch-all** when you want one handler for all file event types.
* For move/copy events, use `FISHOOK_SRC` and `FISHOOK_DST`.

---

### Reference type model

This mirrors the full supported schema.

```ts
// Basic command forms
type SingleRunCmd = string;         // e.g. "npm test"
type RunCmdList = string[];         // e.g. ["npm test", "npm run lint"]
type RunCmd = SingleRunCmd | RunCmdList;

// Shared prelude commands
type Setup = RunCmd;                // runs BEFORE every command (as-is)
type Source = RunCmd;               // runs BEFORE every command (auto-prepends "source")

// Filters (glob patterns)
type FileGlobFilter = string | string[];

// Action specification
type SingleActionSpec = {
  run?: RunCmd;           // run once per hook

  // File events (run per-file)
  onAdd?: RunCmdList;
  onChange?: RunCmdList;
  onDelete?: RunCmdList;
  onMove?: RunCmdList;
  onCopy?: RunCmdList;
  onFileEvent?: RunCmdList; // generic per-file event

  // Ref events (run per-ref)
  onRefEvent?: RunCmdList;
  onRefCreate?: RunCmdList;
  onRefUpdate?: RunCmdList;
  onRefDelete?: RunCmdList;

  // Generic per-event hook entry
  onEvent?: RunCmdList;

  // File filters (apply to file-event commands)
  applyTo?: FileGlobFilter;  // defaults to all
  skipList?: FileGlobFilter; // defaults to none
};

type SingleAction = RunCmd | SingleActionSpec;
type Action = SingleAction | SingleAction[];

// Hook key names (Git hook names)
type Key =
 | 'applypatch-msg'
 | 'pre-applypatch'
 | 'post-applypatch'
 | 'sendemail-validate'
 | 'pre-commit'
 | 'prepare-commit-msg'
 | 'commit-msg'
 | 'post-commit'
 | 'pre-rebase'
 | 'post-checkout'
 | 'post-merge'
 | 'post-rewrite'
 | 'pre-push'
 | 'pre-auto-gc'
 | 'pre-receive'
 | 'update'
 | 'post-receive'
 | 'post-update'
 | 'push-to-checkout'
 | 'proc-receive'
 | 'fsmonitor-watchman';

type Spec = {
  setup?: Setup;
  source?: Source;
  [k in Key]?: Action;
};
```

---

### Top-level keys

#### `setup`

Runs **before every command** exactly as written. Useful for PATH fixes, exports, etc.

```json
{ "setup": "export PATH=$HOME/.local/bin:$PATH" }
```

#### `source`

Runs **before every command**, but fishook will automatically prepend `source`.

```json
{ "source": "$FISHOOK_REPO_ROOT/.venv/bin/activate" }
```

---

### Built-in functions available in hook commands

These are available in the shell context where fishook runs commands:

* `old()` – print old file content
* `new()` – print new file content
* `diff()` – print diff for the current file
* `raise "message"` – fail the hook with a message

Example:

```json
{
  "pre-commit": [
    {
      "applyTo": ["*.js"],
      "onChange": [
        "diff | grep -q '+.*TODO' && echo 'Warning: new TODO in $FISHOOK_PATH'"
      ]
    }
  ]
}
```

---

### Environment variables

These are available to all commands, including `setup` and `source`.

#### Paths & identity

* `FISHOOK_COMMON` – directory containing fishook’s bundled helper scripts
* `FISHOOK_CONFIG_DIR` – directory containing the current config file
* `FISHOOK_REPO_ROOT` – absolute path to repo root
* `FISHOOK_REPO_NAME` – repo directory name

#### Current hook / event context

* `FISHOOK_HOOK` – current hook name
* `FISHOOK_EVENT` – event type (add, change, delete, move, copy)

#### Current file context (file events)

* `FISHOOK_PATH` – file path for add/change/delete
* `FISHOOK_SRC` – source path (move/copy)
* `FISHOOK_DST` – destination path (move/copy)

#### Current ref context (ref events)

* `FISHOOK_REF` – ref name
* `FISHOOK_OLD_OID` – old commit oid
* `FISHOOK_NEW_OID` – new commit oid

#### Remote context (pre-push)

* `FISHOOK_REMOTE_NAME` – remote name
* `FISHOOK_REMOTE_URL` – remote URL

---

### Git hook positional arguments

Fishook does not hide Git’s native hook arguments; they remain available as `$1`, `$2`, ...

Common ones:

* `commit-msg`: `$1` = path to commit message file
* `post-checkout`: `$1` old HEAD, `$2` new HEAD, `$3` checkout flag
* `pre-push`: `$1` remote name, `$2` remote URL (ref updates are on stdin)

---

### Install behavior & options

Fishook installs hook shims into `.git/hooks/`.

If hooks already exist, fishook can:

* overwrite
* chain
* backup

To bypass the interactive prompt (useful in CI), set:

* `FISHOOK_INSTALL_CHOICE`

    * `1` = overwrite
    * `2` = chain
    * `3` = backup

---

### Built-in common utilities

Helpers in `$FISHOOK_COMMON/` (optional):

* `forbid-pattern <pattern> <message>` – fail if a regex matches file content
* `forbid-file-pattern <pattern> <message>` – fail if a regex matches file path
* `ensure-executable` – mark the current file executable
* `modify_commit_message`
* `iter_source <folder>` – source all bash files in a folder
* `pcsed <pattern> <replacement> [--index-only] [--local-only]` – apply sed replacements safely

Example:

```json
{
  "pre-commit": [
    {
      "applyTo": ["*.sh", "scripts/*"],
      "onAdd": ["$FISHOOK_COMMON/ensure-executable.sh"],
      "onChange": ["$FISHOOK_COMMON/ensure-executable.sh"]
    }
  ]
}
```

---

## Requirements

* `git`
* `bash`
* `jq`

## License

Unlicense
