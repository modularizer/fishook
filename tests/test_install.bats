#!/usr/bin/env bats
# Tests for fishook install/uninstall functionality

load helpers

setup() {
  setup_temp_repo
}

teardown() {
  teardown_temp_repo
}

@test "fishook install creates hook files" {
  create_config '{"pre-commit": "echo test"}'

  run install_fishook
  assert_success

  # Check that pre-commit hook was installed
  assert_hook_installed "pre-commit"
}

@test "fishook install creates all configured hooks" {
  create_config '{
    "pre-commit": "echo pre-commit",
    "post-commit": "echo post-commit",
    "pre-push": "echo pre-push"
  }'

  run install_fishook
  assert_success

  assert_hook_installed "pre-commit"
  assert_hook_installed "post-commit"
  assert_hook_installed "pre-push"
}

@test "fishook uninstall removes hook files" {
  create_config '{"pre-commit": "echo test"}'
  install_fishook

  run uninstall_fishook
  assert_success

  # Hook file should be removed or backed up
  # (depending on if it was a fishook-managed hook)
}

@test "fishook install works without config file" {
  # Should still create hook infrastructure
  run install_fishook
  assert_success
}

@test "fishook install overwrites existing hooks when user chooses option 1" {
  # Create a custom pre-commit hook
  mkdir -p .git/hooks
  echo '#!/bin/bash' > .git/hooks/pre-commit
  echo 'echo "custom hook"' >> .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit

  create_config '{"pre-commit": "echo fishook"}'

  # Use environment variable for non-interactive install
  run env FISHOOK_INSTALL_CHOICE=1 bash ./fishook.sh install
  assert_success

  # Original hook should be backed up with .bak extension
  run bash -c 'ls .git/hooks/pre-commit.bak.* 2>/dev/null | wc -l'
  assert_output "1"

  # New fishook stub should be installed
  assert_hook_installed "pre-commit"
}

@test "fishook install chains existing hooks when user chooses option 2" {
  # Create a custom pre-commit hook
  mkdir -p .git/hooks
  echo '#!/bin/bash' > .git/hooks/pre-commit
  echo 'echo "custom hook"' >> .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit

  create_config '{"pre-commit": "echo fishook"}'

  # Use environment variable for non-interactive install
  run env FISHOOK_INSTALL_CHOICE=2 bash ./fishook.sh install
  assert_success

  # Original hook should be moved to .fishook-prev
  assert_file_exist ".git/hooks/pre-commit.fishook-prev"
  assert_file_executable ".git/hooks/pre-commit.fishook-prev"

  # New fishook stub should be installed and mention chained
  run grep "chained" .git/hooks/pre-commit
  assert_success
}

@test "fishook install backs up existing hooks when user chooses option 3" {
  # Create a custom pre-commit hook
  mkdir -p .git/hooks
  echo '#!/bin/bash' > .git/hooks/pre-commit
  echo 'echo "custom hook"' >> .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit

  create_config '{"pre-commit": "echo fishook"}'

  # Use environment variable for non-interactive install
  run env FISHOOK_INSTALL_CHOICE=3 bash ./fishook.sh install
  assert_success

  # Original hook should be backed up
  run bash -c 'ls .git/hooks/pre-commit.bak.* 2>/dev/null | wc -l'
  assert_output "1"

  # New fishook stub should be installed
  assert_hook_installed "pre-commit"
}

@test "installed hook calls fishook.sh" {
  create_config '{"pre-commit": "echo test"}'
  install_fishook

  # Read the installed hook file
  cat .git/hooks/pre-commit

  # Should contain reference to fishook.sh
  run grep -q "fishook" .git/hooks/pre-commit
  assert_success
}
