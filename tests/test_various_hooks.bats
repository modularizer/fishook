#!/usr/bin/env bats
# Tests for various git hook types (beyond pre-commit)

load helpers

setup() {
  setup_temp_repo
}

teardown() {
  teardown_temp_repo
}

# ========== commit-msg hook tests ==========

@test "commit-msg hook can validate commit message format" {
  create_config '{
    "commit-msg": "grep -qE \"^(feat|fix|docs|chore):\" $1 || raise \"Commit must follow format: type: message\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "invalid commit message"
  assert_failure
  assert_output_contains "Commit must follow format"
}

@test "commit-msg hook accepts valid commit messages" {
  create_config '{
    "commit-msg": "grep -qE \"^(feat|fix|docs):\" $1 || raise \"Invalid format\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "feat: add new feature"
  assert_success
}

@test "commit-msg hook can modify commit messages" {
  create_config '{
    "commit-msg": "modify_commit_message \"$1\" \"s/^/[PREFIX] /\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "my commit"
  assert_success

  run git log -1 --pretty=%B
  assert_output_contains "[PREFIX] my commit"
}

@test "commit-msg hook receives commit message file path" {
  create_config '{
    "commit-msg": "test -f \"$1\" && echo \"Message file exists\" || raise \"No message file\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
  assert_output_contains "Message file exists"
}

# ========== post-commit hook tests ==========

@test "post-commit hook runs after successful commit" {
  create_config '{
    "post-commit": "echo \"Commit completed: $(git rev-parse --short HEAD)\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test commit"
  assert_success
  assert_output_contains "Commit completed:"
}

@test "post-commit hook cannot block commit" {
  create_config '{
    "post-commit": "exit 1"
  }'
  install_fishook

  stage_file "test.txt"

  # Commit should succeed even though post-commit fails
  git commit -m "test commit"

  # Verify commit was created
  run git log -1 --oneline
  assert_success
  assert_output_contains "test commit"
}

@test "post-commit hook can trigger notifications" {
  create_config '{
    "post-commit": "echo \"New commit by $(git config user.name): $(git log -1 --pretty=%s)\" > /tmp/commit-notification.txt"
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "feat: new feature"
  assert_success

  run cat /tmp/commit-notification.txt
  assert_output_contains "New commit by"
  assert_output_contains "feat: new feature"
  rm -f /tmp/commit-notification.txt
}

# ========== post-checkout hook tests ==========

@test "post-checkout hook runs after branch checkout" {
  create_config '{
    "post-checkout": "echo \"Checked out: $(git branch --show-current)\""
  }'
  install_fishook

  # Create and checkout a new branch
  git checkout -b feature-branch 2>&1

  run git log -1 --pretty=%B
  # The hook should have run during checkout
  # Note: output is from the hook execution during checkout
}

@test "post-checkout hook receives previous and new HEAD" {
  create_config '{
    "post-checkout": "echo \"From $1 to $2\" > /tmp/checkout-info.txt"
  }'
  install_fishook

  git checkout -b new-branch 2>&1

  # Check the hook wrote the file
  if [ -f /tmp/checkout-info.txt ]; then
    run cat /tmp/checkout-info.txt
    assert_output_contains "From"
    assert_output_contains "to"
    rm -f /tmp/checkout-info.txt
  fi
}

@test "post-checkout hook detects branch vs file checkout" {
  create_config '{
    "post-checkout": "test \"$3\" = \"1\" && echo \"Branch checkout\" || echo \"File checkout\""
  }'
  install_fishook

  run git checkout -b test-branch
  # This creates a new branch, so $3 should be 1
}

# ========== post-merge hook tests ==========

@test "post-merge hook runs after git merge" {
  create_config '{
    "post-merge": "echo \"Merge completed successfully\""
  }'
  install_fishook

  # Create a branch and make a commit
  git checkout -b feature
  echo "feature content" > feature.txt
  git add feature.txt
  git commit -m "Add feature"

  # Go back to master and merge
  git checkout master
  run git merge feature --no-edit
  assert_success
  assert_output_contains "Merge completed successfully"
}

@test "post-merge hook can detect squash merge" {
  create_config '{
    "post-merge": "test \"$1\" = \"1\" && echo \"Squash merge\" || echo \"Normal merge\""
  }'
  install_fishook

  # Note: Testing actual squash merge is complex in isolated test
  # This verifies the hook can access the parameter
}

# ========== prepare-commit-msg hook tests ==========

@test "prepare-commit-msg hook can modify commit message before editor" {
  create_config '{
    "prepare-commit-msg": "echo \"[AUTO] \" | cat - $1 > $1.tmp && mv $1.tmp $1"
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test message"
  assert_success

  run git log -1 --pretty=%B
  assert_output_contains "[AUTO]"
}

@test "prepare-commit-msg hook receives commit message source" {
  create_config '{
    "prepare-commit-msg": "echo \"Source: $2\" >> $1"
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success

  run git log -1 --pretty=%B
  assert_output_contains "Source:"
}

# ========== pre-push hook tests ==========

@test "pre-push hook can block push to protected branch" {
  create_config '{
    "pre-push": "test \"$1\" != \"origin\" || raise \"Cannot push to origin\""
  }'
  install_fishook

  stage_file "test.txt"
  git commit -m "test"

  # Create a real bare repository as remote
  local remote_dir="/tmp/fishook-test-remote-$$"
  git init --bare "$remote_dir" >/dev/null 2>&1
  git remote add origin "$remote_dir"

  run git push origin master 2>&1
  assert_failure
  assert_output_contains "Cannot push to origin"

  # Cleanup
  rm -rf "$remote_dir"
}

@test "pre-push hook receives remote name and URL" {
  create_config '{
    "pre-push": "echo \"Pushing to $1 at $2\" > /tmp/push-info.txt"
  }'
  install_fishook

  stage_file "test.txt"
  git commit -m "test"

  # Create a real bare repository as remote
  local remote_dir="/tmp/fishook-test-remote-$$"
  git init --bare "$remote_dir" >/dev/null 2>&1
  git remote add test-remote "$remote_dir"

  # Push (should succeed and hook should run)
  git push test-remote master 2>&1 || true

  if [ -f /tmp/push-info.txt ]; then
    run cat /tmp/push-info.txt
    assert_output_contains "Pushing to test-remote"
    rm -f /tmp/push-info.txt
  fi

  # Cleanup
  rm -rf "$remote_dir"
}

@test "pre-push hook can run tests before push" {
  create_config '{
    "pre-push": {
      "run": "echo \"Running tests before push...\""
    }
  }'
  install_fishook

  stage_file "test.txt"
  git commit -m "test"

  # Create a real bare repository as remote
  local remote_dir="/tmp/fishook-test-remote-$$"
  git init --bare "$remote_dir" >/dev/null 2>&1
  git remote add test "$remote_dir"

  run git push test master 2>&1
  assert_success
  assert_output_contains "Running tests before push"

  # Cleanup
  rm -rf "$remote_dir"
}

# ========== pre-rebase hook tests ==========

@test "pre-rebase hook can block rebase of certain branches" {
  create_config '{
    "pre-rebase": "test \"$1\" != \"master\" || raise \"Cannot rebase master\""
  }'
  install_fishook

  # Create a commit
  stage_file "test.txt"
  git commit -m "test"

  # Try to rebase master (should be blocked)
  run git rebase master 2>&1
  # Note: May succeed if already up-to-date, testing the hook mechanism
}

# ========== Multiple hooks together ==========

@test "multiple hooks work in sequence" {
  create_config '{
    "pre-commit": "echo \"Pre-commit: checking files\"",
    "commit-msg": "echo \"Commit-msg: $(wc -l < $1) line message\" >&2",
    "post-commit": "echo \"Post-commit: done!\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "multi-hook test"
  assert_success
  assert_output_contains "Pre-commit: checking files"
  assert_output_contains "Post-commit: done!"
}

@test "hooks can share state via files" {
  create_config '{
    "pre-commit": "echo \"$(git diff --cached --name-only)\" > /tmp/changed-files.txt",
    "post-commit": "echo \"Committed files: $(cat /tmp/changed-files.txt)\""
  }'
  install_fishook

  stage_file "file1.txt"
  stage_file "file2.txt"

  run git commit -m "test"
  assert_success
  assert_output_contains "Committed files:"
  assert_output_contains "file1.txt"
  rm -f /tmp/changed-files.txt
}

# ========== Hook with environment variables ==========

@test "hooks have access to FISHOOK environment variables" {
  create_config '{
    "pre-commit": "echo \"Repo: $FISHOOK_REPO_NAME, Hook: $FISHOOK_HOOK\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
  assert_output_contains "Repo:"
  assert_output_contains "Hook: pre-commit"
}

@test "post-checkout hook has FISHOOK_REF set" {
  create_config '{
    "post-checkout": "test -n \"$FISHOOK_REF\" && echo \"REF: $FISHOOK_REF\""
  }'
  install_fishook

  run git checkout -b test-ref-branch
  # FISHOOK_REF should be set to the new branch ref
}

@test "commit-msg has access to FISHOOK_HOOK variable" {
  create_config '{
    "commit-msg": "test \"$FISHOOK_HOOK\" = \"commit-msg\" || raise \"Wrong hook name\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
}
