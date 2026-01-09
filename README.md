# fishook 🐟🪝

**fishook** is a tiny, Git-native hook runner driven by a single `fishook.json` file.

It installs lightweight stubs into `.git/hooks` and lets you define hook behavior declaratively, without locking you into a language, framework, or ecosystem.

* No daemons
* No magic
* No YAML
* Easy to install, easy to remove

---

## Why fishook?

Git hooks are powerful, but:

* `.git/hooks` isn’t versioned
* Hook scripts get messy fast
* Existing tools are often heavy or opinionated

fishook keeps things simple:

* One config file: `fishook.json`
* One runner: `fishook.sh`
* Works with **any language or tool**
* Safe to delete later

If you understand Git hooks, you already understand fishook.

---

## Installation

### Node (npm)

```bash
npm install --save-dev fishook
```

### Python (pip)

```bash
pip install fishook
```

Both install a `fishook` CLI.

---

## Quick start

From your repo root:

```bash
fishook install
```

This will:

1. Install fishook-managed stubs into `.git/hooks`
2. Create a sample `fishook.json` (if one doesn’t exist)
3. Prompt if existing hooks are detected

---

## Usage

```text
fishook

Usage:
  fishook install                     [--config /path/to/fishook.json] [--hooks-path PATH]
  fishook uninstall                   [--hooks-path PATH]
  fishook list
  fishook explain <hook-name>         [--config /path/to/fishook.json]
  fishook <hook-name> [hook-args...]  [--config /path/to/fishook.json] [--dry-run]
```

### Examples

```bash
fishook install
fishook list
fishook explain pre-commit
fishook pre-commit --dry-run
fishook commit-msg .git/COMMIT_EDITMSG
```

---

## `fishook.json`

Place a `fishook.json` in your repo root (default location).

### Basic example

```json
{
  "pre-commit": [
    "npm test",
    "npm run lint"
  ],
  "commit-msg": "scripts/validate-commit-msg.sh"
}
```

### Supported formats

Each hook entry may be:

* **string**

  ```json
  "pre-commit": "npm test"
  ```

* **array of strings** (run in order)

  ```json
  "pre-commit": ["npm test", "npm run lint"]
  ```

* **object**

  ```json
  "pre-commit": { "run": ["npm test"] }
  ```

(`"commands"` is accepted as an alias for `"run"`.)

---

## Environment variables

When a hook runs, fishook sets:

* `GIT_HOOK_KEY` – the hook name (`pre-commit`, `commit-msg`, etc.)
* `GIT_HOOK_ARGS` – shell-quoted arguments Git passed to the hook

Commands are executed via:

```bash
bash -lc "<command> [hook-args...]"
```

---

## Manual testing

You can run hooks manually at any time:

```bash
fishook pre-commit
fishook pre-commit --dry-run
fishook commit-msg .git/COMMIT_EDITMSG
```

`--dry-run` prints commands without executing them.

---

## Existing hooks

During `fishook install`, if a hook already exists, you’ll be prompted to:

1. **Overwrite** – replace it with fishook
2. **Chain** – preserve it and run it before fishook
3. **Backup** – move it aside without chaining

Uninstalling restores chained hooks automatically.

---

## Server-side hooks

fishook supports server-side hook names (`pre-receive`, `update`, etc.), but:

> GitHub, GitLab.com, and Bitbucket **do not run custom server-side hooks**.

Those hooks only apply if you control the Git server (self-hosted Git, Gerrit, GitLab self-hosted).

---

## Requirements

* `git`
* `bash`
* `jq`

fishook intentionally relies on standard tools and avoids vendoring dependencies.

---

## Uninstall

```bash
fishook uninstall
```

Removes fishook-managed stubs and restores any chained hooks.

---

## Philosophy

fishook is designed to be:

* **transparent**
* **boring**
* **reversible**

If you stop liking it, delete `fishook.json` and uninstall.
No lock-in, no hidden state.

---

## License

UnLicense
