#!/usr/bin/env bash
# Test helper functions for BATS tests

# Load BATS libraries
load '../node_modules/bats-support/load'
load '../node_modules/bats-assert/load'

# Path to fishook.sh (relative to tests directory)
FISHOOK_SH="${BATS_TEST_DIRNAME}/../fishook.sh"

# Custom file assertion helpers
assert_file_exist() {
  local file="$1"
  [[ -f "$file" ]] || {
    echo "Expected file to exist: $file"
    return 1
  }
}

assert_file_not_exist() {
  local file="$1"
  [[ ! -f "$file" ]] || {
    echo "Expected file to not exist: $file"
    return 1
  }
}

assert_file_executable() {
  local file="$1"
  [[ -x "$file" ]] || {
    echo "Expected file to be executable: $file"
    return 1
  }
}

# Setup a temporary git repository for testing
setup_temp_repo() {
  # Create temporary directory
  export TEST_TEMP_DIR="$(mktemp -d -t fishook-test.XXXXXX)"
  export OLD_PWD="$PWD"
  cd "$TEST_TEMP_DIR"

  # Copy fishook.sh and common/ directory into test repo
  # This ensures hooks can find fishook.sh
  cp "$FISHOOK_SH" .
  cp -r "${BATS_TEST_DIRNAME}/../common" .

  # Initialize git repo
  git init --quiet
  git config user.email "test@fishook.test"
  git config user.name "Fishook Test"
  git config commit.gpgsign false

  # Create an initial commit (some hooks need at least one commit)
  echo "# Test Repo" > README.md
  git add README.md
  git commit --quiet -m "Initial commit"
}

# Teardown temporary repository
teardown_temp_repo() {
  if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
    cd "$OLD_PWD"
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# Install fishook hooks in the current test repo
install_fishook() {
  bash ./fishook.sh install
}

# Uninstall fishook hooks
uninstall_fishook() {
  bash ./fishook.sh uninstall
}

# Create a fishook.json config file
create_config() {
  local config_content="$1"
  echo "$config_content" > fishook.json
}

# Run fishook for a specific hook
run_fishook_hook() {
  local hook_name="$1"
  shift
  bash ./fishook.sh "$hook_name" "$@"
}

# Assert that a git hook file exists and is executable
assert_hook_installed() {
  local hook_name="$1"
  local hook_path=".git/hooks/$hook_name"
  assert_file_exist "$hook_path"
  assert_file_executable "$hook_path"
}

# Assert that a git hook file does not exist
assert_hook_not_installed() {
  local hook_name="$1"
  local hook_path=".git/hooks/$hook_name"
  assert_file_not_exist "$hook_path"
}

# Create a file and stage it for commit
stage_file() {
  local filename="$1"
  local content="${2:-test content}"
  echo "$content" > "$filename"
  git add "$filename"
}

# Assert command output contains a string (case-insensitive)
assert_output_contains() {
  local expected="$1"
  [[ "$output" == *"$expected"* ]] || {
    echo "Expected output to contain: $expected"
    echo "Actual output: $output"
    return 1
  }
}
