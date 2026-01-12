#!/usr/bin/env bats
# Integration tests for fishook hook execution

load helpers

setup() {
  setup_temp_repo
}

teardown() {
  teardown_temp_repo
}

@test "simple pre-commit hook runs successfully" {
  create_config '{"pre-commit": "echo Hello from fishook"}'
  install_fishook

  stage_file "test.txt" "test content"

  run git commit -m "test commit"
  assert_success
  assert_output_contains "Hello from fishook"
}

@test "pre-commit hook can fail and block commit" {
  create_config '{"pre-commit": "exit 1"}'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test commit"
  assert_failure
}

@test "post-commit hook runs after successful commit" {
  create_config '{"post-commit": "echo Post-commit executed"}'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test commit"
  assert_success
  assert_output_contains "Post-commit executed"
}

@test "multiple commands in run array format execute in sequence" {
  create_config '{
    "pre-commit": {
      "run": [
        "echo First command",
        "echo Second command"
      ]
    }
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test commit"
  assert_success
  assert_output_contains "First command"
  assert_output_contains "Second command"
}

@test "hook with run property executes command" {
  create_config '{
    "pre-commit": {
      "run": "echo Running from object format"
    }
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test commit"
  assert_success
  assert_output_contains "Running from object format"
}

@test "onFileEvent runs when file is staged" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "echo Processing file: $FISHOOK_PATH"
    }
  }'
  install_fishook

  stage_file "myfile.txt"

  run git commit -m "test commit"
  assert_success
  assert_output_contains "Processing file:"
  assert_output_contains "myfile.txt"
}

@test "applyTo filter only processes matching files" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "echo JavaScript file found",
      "applyTo": ["*.js"]
    }]
  }'
  install_fishook

  stage_file "test.js" "console.log('test')"
  stage_file "test.txt" "plain text"

  run git commit -m "test commit"
  assert_success
  assert_output_contains "JavaScript file found"
}

@test "skipList filter excludes matching files" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "echo Processing: $FISHOOK_PATH",
      "skipList": ["*.md"]
    }]
  }'
  install_fishook

  stage_file "test.js" "code"
  stage_file "README.md" "docs"

  run git commit -m "test commit"
  assert_success
  assert_output_contains "test.js"
  refute_output --partial "README.md"
}

@test "dry-run mode prevents command execution" {
  create_config '{"pre-commit": "echo This should not execute in dry-run"}'

  stage_file "test.txt"

  run run_fishook_hook pre-commit --dry-run
  assert_success

  # In dry-run mode, commands should NOT execute
  # So we should NOT see the echo output
  refute_output --partial "This should not execute in dry-run"
}

@test "fishook list shows available hooks" {
  create_config '{
    "pre-commit": "echo test",
    "post-commit": "echo test2"
  }'

  run bash ./fishook.sh list
  assert_success
  assert_output_contains "pre-commit"
  assert_output_contains "post-commit"
}

@test "fishook explain shows hook configuration" {
  create_config '{"pre-commit": "echo Hello"}'

  run bash ./fishook.sh explain pre-commit
  assert_success
  assert_output_contains "pre-commit"
}

@test "empty hook block in array is skipped" {
  create_config '{
    "pre-commit": [
      {"onFileEvent": "echo First"},
      {},
      {"onFileEvent": "echo Third"}
    ]
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test commit"
  assert_success
  assert_output_contains "First"
  assert_output_contains "Third"
}
