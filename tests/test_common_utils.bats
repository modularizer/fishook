#!/usr/bin/env bats
# Tests for all common/ utilities

load helpers

setup() {
  setup_temp_repo
}

teardown() {
  teardown_temp_repo
}

# ========== forbid-file-pattern tests ==========

@test "forbid_file_pattern blocks files matching pattern" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "forbid_file_pattern \"\\.env\" \"Environment files should not be committed\""
    }
  }'
  install_fishook

  stage_file ".env" "SECRET_KEY=12345"

  run git commit -m "test commit"
  assert_failure
  assert_output_contains "Environment files should not be committed"
}

@test "forbid_file_pattern allows files not matching pattern" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "forbid_file_pattern \"\\.env\" \"No .env files\""
    }
  }'
  install_fishook

  stage_file "config.txt" "NORMAL_CONFIG=value"

  run git commit -m "test commit"
  assert_success
}

@test "forbid_file_pattern works with regex patterns" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "forbid_file_pattern \"(secret|password|credential)\" \"Sensitive files detected\""
    }
  }'
  install_fishook

  stage_file "credentials.json" "{}"

  run git commit -m "test commit"
  assert_failure
  assert_output_contains "Sensitive files detected"
}

@test "forbid_file_pattern blocks specific file extensions" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "forbid_file_pattern \"\\.tmp$\" \"Temporary files should not be committed\"",
      "applyTo": ["*.tmp"]
    }]
  }'
  install_fishook

  stage_file "test.tmp" "temporary data"

  run git commit -m "test commit"
  assert_failure
  assert_output_contains "Temporary files should not be committed"
}

# ========== pcsed tests ==========

@test "pcsed applies sed transformation to staged file" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "pcsed \"s/foo/bar/g\"",
      "applyTo": ["*.txt"]
    }]
  }'
  install_fishook

  echo "foo foo foo" > test.txt
  git add test.txt

  run git commit -m "test commit"
  assert_success

  # Check that staged content was modified
  run git show HEAD:test.txt
  assert_output_contains "bar bar bar"
}

@test "pcsed with --index-only modifies only staged content" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "pcsed --index-only \"s/old/new/g\"",
      "applyTo": ["*.txt"]
    }]
  }'
  install_fishook

  echo "old content" > file.txt
  git add file.txt

  run git commit -m "test commit"
  assert_success

  # Staged/committed content should be modified
  run git show HEAD:file.txt
  assert_output "new content"

  # But worktree should still have original
  run cat file.txt
  assert_output "old content"
}

@test "pcsed replaces multiple occurrences with g flag" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "pcsed \"s/test/prod/g\""
    }]
  }'
  install_fishook

  echo "test test test" > config.txt
  git add config.txt

  run git commit -m "test commit"
  assert_success

  run git show HEAD:config.txt
  assert_output "prod prod prod"
}

@test "pcsed with regex pattern replacement" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "pcsed \"s/version = [0-9.]+/version = 2.0.0/\""
    }]
  }'
  install_fishook

  echo "version = 1.5.3" > version.txt
  git add version.txt

  run git commit -m "test commit"
  assert_success

  run git show HEAD:version.txt
  assert_output "version = 2.0.0"
}

@test "pcsed does nothing if pattern does not match" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "pcsed \"s/nonexistent/replacement/\""
    }]
  }'
  install_fishook

  echo "original content" > file.txt
  git add file.txt

  run git commit -m "test commit"
  assert_success

  run git show HEAD:file.txt
  assert_output "original content"
}

# ========== scope.sh helper functions tests ==========

@test "new() function returns staged file content" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "test \"$(new | head -1)\" = \"staged content\" || raise \"Expected staged content\""
    }
  }'
  install_fishook

  echo "staged content" > test.txt
  git add test.txt

  run git commit -m "test commit"
  assert_success
}

@test "old() function returns previous version of file" {
  create_config '{
    "pre-commit": {
      "onChange": "test \"$(old)\" = \"original\" || raise \"Expected original content\""
    }
  }'
  install_fishook

  # Create and commit initial version
  echo "original" > test.txt
  git add test.txt
  git commit -m "Initial version"

  # Modify it
  echo "modified" > test.txt
  git add test.txt

  run git commit -m "Modify file"
  assert_success
}

@test "diff() function shows changes between versions" {
  create_config '{
    "pre-commit": {
      "onChange": "diff | grep -q \"^+modified\" || raise \"Expected to see modified line\""
    }
  }'
  install_fishook

  # Create initial version
  echo "original" > test.txt
  git add test.txt
  git commit -m "Initial"

  # Modify it
  echo "modified" > test.txt
  git add test.txt

  run git commit -m "Change file"
  assert_success
}

# ========== Combined utility tests ==========

@test "multiple utilities can be used together" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": [
        "forbid_pattern \"DEBUG\" \"Remove debug code\"",
        "pcsed \"s/console\\.log/logger.info/g\""
      ],
      "applyTo": ["*.js"]
    }]
  }'
  install_fishook

  echo "console.log('hello');" > app.js
  git add app.js

  run git commit -m "test commit"
  assert_success

  # Check sed replacement worked
  run git show HEAD:app.js
  assert_output_contains "logger.info"
}

@test "utility works with skipList filter" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "forbid_pattern \"TODO\" \"No TODOs allowed\"",
      "skipList": ["*.md"]
    }]
  }'
  install_fishook

  # TODO in markdown should be allowed
  echo "# TODO: write docs" > README.md
  git add README.md

  run git commit -m "test commit"
  assert_success
}

@test "raise function aborts with error message" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "raise \"Custom error message\""
    }
  }'
  install_fishook

  stage_file "test.txt" "content"

  run git commit -m "test commit"
  assert_failure
  assert_output_contains "Custom error message"
}
