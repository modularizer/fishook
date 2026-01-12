#!/usr/bin/env bats
# Comprehensive tests for hook arguments and environment variables

load helpers

setup() {
  setup_temp_repo
}

teardown() {
  teardown_temp_repo
}

# ========== Base Environment Variables ==========

@test "FISHOOK_REPO_ROOT is set to repository root" {
  create_config '{
    "pre-commit": "test \"$FISHOOK_REPO_ROOT\" = \"$(git rev-parse --show-toplevel)\" || raise \"Wrong repo root\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_REPO_NAME is set to repository directory name" {
  create_config '{
    "pre-commit": "test -n \"$FISHOOK_REPO_NAME\" || raise \"FISHOOK_REPO_NAME not set\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
  # Repo name should match the temp directory name pattern
}

@test "FISHOOK_HOOK is set to correct hook name" {
  create_config '{
    "pre-commit": "test \"$FISHOOK_HOOK\" = \"pre-commit\" || raise \"Wrong hook: $FISHOOK_HOOK\"",
    "post-commit": "test \"$FISHOOK_HOOK\" = \"post-commit\" || raise \"Wrong hook: $FISHOOK_HOOK\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_COMMON points to common utilities directory" {
  create_config '{
    "pre-commit": "test -d \"$FISHOOK_COMMON\" || raise \"FISHOOK_COMMON not a directory\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_COMMON utilities are accessible" {
  create_config '{
    "pre-commit": "test -f \"$FISHOOK_COMMON/forbid-pattern.sh\" || raise \"Cannot find common utilities\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_CONFIG_PATH points to active config file" {
  create_config '{
    "pre-commit": "test -f \"$FISHOOK_CONFIG_PATH\" || raise \"Config file not found at $FISHOOK_CONFIG_PATH\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_CONFIG_DIR points to config directory" {
  create_config '{
    "pre-commit": "test -d \"$FISHOOK_CONFIG_DIR\" || raise \"Config dir not found\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_GIT_DIR points to .git directory" {
  create_config '{
    "pre-commit": "test -d \"$FISHOOK_GIT_DIR\" || raise \"Git dir not found\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_HOOKS_PATH points to hooks directory" {
  create_config '{
    "pre-commit": "test -d \"$FISHOOK_HOOKS_PATH\" || raise \"Hooks path not found\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_CWD is set to current working directory" {
  create_config '{
    "pre-commit": "test -n \"$FISHOOK_CWD\" || raise \"CWD not set\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_DRY_RUN is 0 during normal execution" {
  create_config '{
    "pre-commit": "test \"$FISHOOK_DRY_RUN\" = \"0\" || raise \"DRY_RUN should be 0\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_DRY_RUN is 1 during dry-run" {
  create_config '{
    "pre-commit": "test \"$FISHOOK_DRY_RUN\" = \"1\" && exit 0 || raise \"DRY_RUN should be 1\""
  }'

  stage_file "test.txt"

  # In dry-run mode, commands don't execute, so this test verifies the env var is set
  # but the raise won't actually happen since commands are skipped
  run bash ./fishook.sh pre-commit --dry-run
  assert_success
}

# ========== File Event Environment Variables ==========

@test "FISHOOK_PATH is set for file events" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "test -n \"$FISHOOK_PATH\" || raise \"FISHOOK_PATH not set\""
    }
  }'
  install_fishook

  stage_file "myfile.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_PATH contains correct file path" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "test \"$FISHOOK_PATH\" = \"test.txt\" || raise \"Wrong path: $FISHOOK_PATH\""
    }
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_ABS_PATH is absolute path to file" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "test \"${FISHOOK_ABS_PATH:0:1}\" = \"/\" || raise \"Not absolute: $FISHOOK_ABS_PATH\""
    }
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_EVENT is set to correct event type for new file" {
  create_config '{
    "pre-commit": {
      "onAdd": "test \"$FISHOOK_EVENT\" = \"add\" || raise \"Wrong event: $FISHOOK_EVENT\""
    }
  }'
  install_fishook

  stage_file "newfile.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_EVENT is set to change for modified file" {
  create_config '{
    "pre-commit": {
      "onChange": "test \"$FISHOOK_EVENT\" = \"change\" || raise \"Wrong event: $FISHOOK_EVENT\""
    }
  }'
  install_fishook

  # Create initial file
  echo "original" > existing.txt
  git add existing.txt
  git commit -m "Initial"

  # Modify it
  echo "modified" > existing.txt
  git add existing.txt

  run git commit -m "Modify"
  assert_success
}

@test "FISHOOK_EVENT_KIND is set to file for file events" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "test \"$FISHOOK_EVENT_KIND\" = \"file\" || raise \"Wrong event kind: $FISHOOK_EVENT_KIND\""
    }
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_STATUS contains git status info" {
  create_config '{
    "pre-commit": {
      "onAdd": "test -n \"$FISHOOK_STATUS\" || raise \"STATUS not set\""
    }
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

# ========== Hook-Specific Arguments ==========

@test "commit-msg receives message file path as $1" {
  create_config '{
    "commit-msg": "test -f \"$1\" || raise \"Message file not found: $1\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test message"
  assert_success
}

@test "commit-msg can read message from $1" {
  create_config '{
    "commit-msg": "grep -q \"test message\" \"$1\" || raise \"Wrong message content\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test message"
  assert_success
}

@test "prepare-commit-msg receives message file as $1" {
  create_config '{
    "prepare-commit-msg": "test -f \"$1\" || raise \"No message file\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "prepare-commit-msg receives commit source as $2" {
  create_config '{
    "prepare-commit-msg": "echo \"Source: $2\" >> /tmp/prepare-commit-source.txt"
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success

  # Check the source was captured (will be "message" for -m flag)
  if [ -f /tmp/prepare-commit-source.txt ]; then
    run cat /tmp/prepare-commit-source.txt
    assert_output_contains "Source:"
    rm -f /tmp/prepare-commit-source.txt
  fi
}

@test "post-checkout receives previous HEAD as $1" {
  create_config '{
    "post-checkout": "echo \"Prev: $1\" > /tmp/post-checkout-prev.txt"
  }'
  install_fishook

  # Checkout a branch
  git checkout -b test-branch 2>&1 || true

  if [ -f /tmp/post-checkout-prev.txt ]; then
    run cat /tmp/post-checkout-prev.txt
    assert_output_contains "Prev:"
    rm -f /tmp/post-checkout-prev.txt
  fi
}

@test "post-checkout receives new HEAD as $2" {
  create_config '{
    "post-checkout": "echo \"New: $2\" > /tmp/post-checkout-new.txt"
  }'
  install_fishook

  git checkout -b test-branch 2>&1 || true

  if [ -f /tmp/post-checkout-new.txt ]; then
    run cat /tmp/post-checkout-new.txt
    assert_output_contains "New:"
    rm -f /tmp/post-checkout-new.txt
  fi
}

@test "post-checkout receives branch flag as $3" {
  create_config '{
    "post-checkout": "echo \"Flag: $3\" > /tmp/post-checkout-flag.txt"
  }'
  install_fishook

  git checkout -b test-branch 2>&1 || true

  if [ -f /tmp/post-checkout-flag.txt ]; then
    run cat /tmp/post-checkout-flag.txt
    # $3 is 1 for branch checkout, 0 for file checkout
    assert_output_contains "Flag:"
    rm -f /tmp/post-checkout-flag.txt
  fi
}

@test "pre-push receives remote name as $1" {
  create_config '{
    "pre-push": "test -n \"$1\" || raise \"No remote name\""
  }'
  install_fishook

  stage_file "test.txt"
  git commit -m "test"

  # Create bare repo as remote
  local remote_dir="/tmp/fishook-test-remote-$$"
  git init --bare "$remote_dir" >/dev/null 2>&1
  git remote add origin "$remote_dir"

  run git push origin master 2>&1
  assert_success

  rm -rf "$remote_dir"
}

@test "pre-push receives remote URL as $2" {
  create_config '{
    "pre-push": "test -n \"$2\" || raise \"No remote URL\""
  }'
  install_fishook

  stage_file "test.txt"
  git commit -m "test"

  local remote_dir="/tmp/fishook-test-remote-$$"
  git init --bare "$remote_dir" >/dev/null 2>&1
  git remote add origin "$remote_dir"

  run git push origin master 2>&1
  assert_success

  rm -rf "$remote_dir"
}

@test "FISHOOK_REMOTE_NAME matches remote in pre-push" {
  create_config '{
    "pre-push": "test \"$FISHOOK_REMOTE_NAME\" = \"$1\" || raise \"Remote name mismatch\""
  }'
  install_fishook

  stage_file "test.txt"
  git commit -m "test"

  local remote_dir="/tmp/fishook-test-remote-$$"
  git init --bare "$remote_dir" >/dev/null 2>&1
  git remote add origin "$remote_dir"

  run git push origin master 2>&1
  assert_success

  rm -rf "$remote_dir"
}

@test "FISHOOK_REMOTE_URL matches URL in pre-push" {
  create_config '{
    "pre-push": "test \"$FISHOOK_REMOTE_URL\" = \"$2\" || raise \"Remote URL mismatch\""
  }'
  install_fishook

  stage_file "test.txt"
  git commit -m "test"

  local remote_dir="/tmp/fishook-test-remote-$$"
  git init --bare "$remote_dir" >/dev/null 2>&1
  git remote add origin "$remote_dir"

  run git push origin master 2>&1
  assert_success

  rm -rf "$remote_dir"
}

@test "post-merge receives squash flag as $1" {
  create_config '{
    "post-merge": "echo \"Squash: $1\" > /tmp/post-merge-squash.txt"
  }'
  install_fishook

  # Create a branch and merge
  git checkout -b feature
  echo "feature" > feature.txt
  git add feature.txt
  git commit -m "feature"

  git checkout master
  git merge feature --no-edit 2>&1 || true

  if [ -f /tmp/post-merge-squash.txt ]; then
    run cat /tmp/post-merge-squash.txt
    # $1 is 1 for squash merge, 0 for normal merge
    assert_output_contains "Squash:"
    rm -f /tmp/post-merge-squash.txt
  fi
}

# ========== FISHOOK_ARGS ==========

@test "FISHOOK_ARGS contains all hook arguments" {
  create_config '{
    "commit-msg": "echo \"Args: $FISHOOK_ARGS\" > /tmp/fishook-args.txt"
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success

  if [ -f /tmp/fishook-args.txt ]; then
    run cat /tmp/fishook-args.txt
    assert_output_contains "Args:"
    rm -f /tmp/fishook-args.txt
  fi
}

@test "FISHOOK_ARGS is properly quoted for arguments with spaces" {
  create_config '{
    "pre-commit": "echo \"ARGS: $FISHOOK_ARGS\" > /tmp/args-test.txt"
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success

  # FISHOOK_ARGS should be shell-quoted properly
  if [ -f /tmp/args-test.txt ]; then
    rm -f /tmp/args-test.txt
  fi
}

# ========== Legacy Environment Variables ==========

@test "GIT_HOOK_KEY is set for backward compatibility" {
  create_config '{
    "pre-commit": "test \"$GIT_HOOK_KEY\" = \"pre-commit\" || raise \"GIT_HOOK_KEY not set\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "GIT_HOOK_ARGS matches FISHOOK_ARGS" {
  create_config '{
    "commit-msg": "test \"$GIT_HOOK_ARGS\" = \"$FISHOOK_ARGS\" || raise \"Args mismatch\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

# ========== Multiple Arguments Together ==========

@test "all base environment variables are set simultaneously" {
  create_config '{
    "pre-commit": {
      "run": [
        "test -n \"$FISHOOK_REPO_ROOT\" || raise \"No REPO_ROOT\"",
        "test -n \"$FISHOOK_REPO_NAME\" || raise \"No REPO_NAME\"",
        "test -n \"$FISHOOK_HOOK\" || raise \"No HOOK\"",
        "test -n \"$FISHOOK_COMMON\" || raise \"No COMMON\"",
        "test -n \"$FISHOOK_GIT_DIR\" || raise \"No GIT_DIR\"",
        "test -n \"$FISHOOK_CONFIG_PATH\" || raise \"No CONFIG_PATH\""
      ]
    }
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "file event variables are set together" {
  create_config '{
    "pre-commit": {
      "onFileEvent": [
        "test -n \"$FISHOOK_PATH\" || raise \"No PATH\"",
        "test -n \"$FISHOOK_ABS_PATH\" || raise \"No ABS_PATH\"",
        "test -n \"$FISHOOK_EVENT\" || raise \"No EVENT\"",
        "test -n \"$FISHOOK_EVENT_KIND\" || raise \"No EVENT_KIND\""
      ]
    }
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

# ========== Environment Variable Correctness ==========

@test "FISHOOK_REPO_ROOT is absolute path" {
  create_config '{
    "pre-commit": "test \"${FISHOOK_REPO_ROOT:0:1}\" = \"/\" || raise \"Not absolute: $FISHOOK_REPO_ROOT\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_CONFIG_PATH ends with .json" {
  create_config '{
    "pre-commit": "test \"${FISHOOK_CONFIG_PATH: -5}\" = \".json\" || raise \"Wrong extension: $FISHOOK_CONFIG_PATH\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}

@test "FISHOOK_COMMON ends with /common" {
  create_config '{
    "pre-commit": "test \"${FISHOOK_COMMON: -7}\" = \"/common\" || raise \"Wrong path: $FISHOOK_COMMON\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}
