# fishook 🐟🪝

Tiny git hook runner driven by `fishook.json`

## Install (coming soon)

### With node
```bash
npm install --save-dev fishook  # (runs fishhook install during postinstall)
```

### With pip
```bash
pip install fishook
fishhook install                # install hooks
```

## Usage
For the most part, you don't even need to use the CLI, just edit the `fishook.json` file in your repo, and those commands will be run automatically.

### Basic
```json
{
  "pre-commit": "npm test",
  "post-checkout": "echo 'Nice! You checked out ${FISHOOK_REF}'"
}
```

### Complex
```json
{
  "setup": "export PATH=$HOME/.local/bin:$PATH",
  "source": "$FISHOOK_REPO_ROOT/.venv/bin/activate",
  "pre-commit": [
    {
      "run": ["npm test", "npm run lint"],
      "applyTo": ["*.js", "*.ts"],
      "skipList": ["vendor/**", "*.min.js", "dist/**"],
      "onChange": [
        "new | grep -q 'console.log' && raise 'Remove console.log before committing'",
        "new | grep -q 'debugger' && raise 'Remove debugger statements'"
      ]
    },
    {
      "applyTo": ["package.json", "package-lock.json"],
      "onChange": [
        "test -f package-lock.json && npm ci --dry-run || raise 'package-lock.json out of sync'"
      ]
    },
    {
      "applyTo": ["src/**/*.{js,ts,jsx,tsx}"],
      "onAdd": [
        "test $(new | wc -c) -lt 100000 || raise 'File too large (>100KB)'"
      ],
      "onChange": [
        "diff | grep -q '+.*TODO' && echo 'Warning: New TODO added in $FISHOOK_PATH'"
      ]
    },
    {
      "skipList": ["*.md", "docs/**"],
      "onFileEvent": [
        "new | grep -qiE '(password|secret|api[_-]?key)\\s*=\\s*[\"'\\'''][^\"'\\''']' && raise 'Potential secret detected'"
      ]
    }
  ],
  "commit-msg": [
    "grep -qE '^(feat|fix|docs|style|refactor|test|chore)(\\(.+\\))?!?:' $1 || raise 'Commit message must follow conventional commits format'"
  ],
  "pre-push": {
    "onRefUpdate": [
      "test \"$FISHOOK_REF\" != 'refs/heads/main' || raise 'Direct push to main blocked. Create a PR instead.'"
    ]
  }
}
```


## Available Hooks supported by git
#### Client-side (patch / email workflows)
* `applypatch-msg`     Runs during git am after extracting a patch commit message; validate/edit the message.
* `pre-applypatch`     Runs during git am before committing the applied patch; can reject.
* `post-applypatch`    Runs during git am after committing; notification only.
* `sendemail-validate` Runs during git send-email to validate outgoing patch email; can reject.

#### Client-side (commit workflow)
* `pre-commit`         Runs before a commit is created; commonly lint/tests/format checks; can reject.
* `pre-merge-commit`   Runs before creating a merge commit (when merge is clean); can reject.
* `prepare-commit-msg` Runs before commit message editor opens; can prefill/edit message.
* `commit-msg`         Runs after message is written; validate commit message; can reject.
* `post-commit`        Runs after commit is created; notification only.

#### Client-side (branch / history changes)
* `pre-rebase`         Runs before rebase starts; can reject.
* `post-checkout `     Runs after checkout/switch; args old/new/flag.
* `post-merge`         Runs after merge; arg is squash flag.
* `post-rewrite`       Runs after commit rewriting; arg is rewrite command; stdin has old/new oids.

#### Client-side (push / maintenance)
* `pre-push`           Runs before pushing; args remote_name/remote_url; stdin lists ref updates.
* `pre-auto-gc`        Runs before git gc --auto; can abort.

#### Server-side (bare repo / self-hosted only; not GitHub/GitLab.com)
* `pre-receive`        Server-side: before accepting pushed refs; stdin old/new/ref triples. Not run on GitHub.
* `update`             Server-side: per-ref update check; args ref/old/new. Not run on GitHub.
* `post-receive`       Server-side: after refs updated; stdin old/new/ref triples. Not run on GitHub.
* `post-update`        Server-side: after refs updated; args are ref names. Not run on GitHub.
* `push-to-checkout`   Server-side: when pushing to checked-out branch with updateInstead. Not run on GitHub.
* `proc-receive`       Server-side: advanced receive-pack protocol hook. Not run on GitHub.

#### Performance
* `fsmonitor-watchman` Used by core.fsmonitor to speed status; reports changed files.

## CLI
The following commands are available:
```bash
fishook                              # general help
fishook install                      # install hooks
fishook list                         # show all available hooks
fishook explain pre-commit           # explain a hook
fishook pre-commit --dry-run         # test manually
fishook pre-commit                   # run the hook manually
fishook uninstall                    # remove
```

## Formats
`fishhook.json` supports a variety of formats ranging from 
* simple (just a string command or a list of commands) ... 
* to complex (multiple actions per hook, each ignoring or applying to only certain files)

Hopefully this explains the various options:
```typescript
type SingleRunCmd = string; // e.g. "pre-commit": "echo foo",
type RunCmdList = string[]; // e.g. "pre-commit": ["echo foo", "echo bar"],
type RunCmd = SingleRunCmd | RunCmdList;
type Setup = SingleRunCmd | RunCmdList; // runs BEFORE every command (as-is)
type Source = SingleRunCmd | RunCmdList; // runs BEFORE every command (auto-prepends "source")
type FileGlobFilter = string | string[]; // glob or array of globs applied to filepaths
type SingleActionSpec = {
    run: RunCmd, // execute once per hook
    onAdd?: RunCmdList, // called once per file added
    onChange?: RunCmdList, // called once per file changed
    onDelete?: RunCmdList, // called once per file deleted
    onMove?: RunCmdList, // called once per file moved
    onCopy?: RunCmdList, // called once per file copied
    onFileEvent?: RunCmdList, // called per file event
    onRefEvent?: RunCmdList, // called per ref event
    onRefCreate?: RunCmdList, // called per ref create event
    onRefUpdate?: RunCmdList, // called per ref update event
    onRefDelete?: RunCmdList, // called per ref delete event
    onEvent?: RunCmdList, // called per event
    applyTo?: FileGlobFilter, // file-event filter (defaults to all)
    skipList?: FileGlobFilter, // file-event filter (defaults to none)
}
type SingleAction = RunCmd | SingleActionSpec;
type Action = SingleAction | SingleAction[];
type Key = |
 'applypatch-msg' |
 'pre-applypatch' |
 'post-applypatch' |
 'sendemail-validate' |
 'pre-commit' |
 'prepare-commit-msg' |
 'commit-msg' |
 'post-commit' |
 'pre-rebase' |
 'post-checkout' |
 'post-merge' |
 'post-rewrite' |
 'pre-push' |
 'pre-auto-gc' |
 'pre-receive' |
 'update' |
 'post-receive' |
 'post-update' |
 'push-to-checkout' |
 'proc-receive' |
 'fsmonitor-watchman';
type Spec = {
    setup?: Setup, // top-level: runs before every command (e.g. export PATH)
    source?: Source, // top-level: auto-sources files before every command (e.g. ".venv/bin/activate")
    [k: Key]: Action
}
```

## Scope
Available in all commands (including `setup` and `source`):

### Functions
- `old()` - get old file content
- `new()` - get new file content
- `diff()` - show diff
- `raise "msg"` - fail hook with message

### Environment Variables
- `FISHOOK_REPO_ROOT` - absolute path to repo root (use this for paths!)
- `FISHOOK_REPO_NAME` - repo directory name
- `FISHOOK_HOOK` - hook name (pre-commit, commit-msg, etc)
- `FISHOOK_EVENT` - event type (add, change, delete, move, copy)
- `FISHOOK_PATH` - file path (add/change/delete)
- `FISHOOK_SRC`, `FISHOOK_DST` - source/dest (move/copy)
- `FISHOOK_REF` - ref name (ref events)
- `FISHOOK_OLD_OID`, `FISHOOK_NEW_OID` - commit oids

## Requirements

- `git`, `bash`, `jq`

## License

UnLicense
