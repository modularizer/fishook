#!/usr/bin/env bats
# Tests for fishook helper utilities in common/

load helpers

setup() {
  setup_temp_repo
}

teardown() {
  teardown_temp_repo
}

@test "forbid_pattern blocks commits with forbidden patterns" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "forbid_pattern \"SECRET\" \"No secrets allowed!\""
    }
  }'
  install_fishook

  stage_file "config.txt" "PASSWORD=SECRET123"

  run git commit -m "test commit"
  assert_failure
  assert_output_contains "No secrets allowed!"
}

@test "forbid_pattern allows commits without forbidden patterns" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "forbid_pattern \"SECRET\" \"No secrets!\""
    }
  }'
  install_fishook

  stage_file "config.txt" "NORMAL_CONFIG=value"

  run git commit -m "test commit"
  assert_success
}

@test "forbid_pattern works with regex patterns" {
  create_config '{
    "pre-commit": {
      "onFileEvent": "forbid_pattern \"(password|secret|api[_-]?key)\" \"Credential detected\""
    }
  }'
  install_fishook

  stage_file "test.txt" "api_key=12345"

  run git commit -m "test commit"
  assert_failure
  assert_output_contains "Credential detected"
}

@test "ensure_executable makes non-executable shell scripts executable" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "ensure_executable",
      "applyTo": ["*.sh"]
    }]
  }'
  install_fishook

  # Create a non-executable shell script
  echo '#!/bin/bash' > script.sh
  echo 'echo "test"' >> script.sh
  chmod -x script.sh
  git add script.sh

  run git commit -m "Add script"
  assert_success
  assert_output_contains "Made executable: script.sh"

  # Verify the file is now executable
  assert [ -x script.sh ]
}

@test "ensure_executable skips already executable files" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "ensure_executable",
      "applyTo": ["*.sh"]
    }]
  }'
  install_fishook

  # Create an executable shell script
  echo '#!/bin/bash' > script.sh
  chmod +x script.sh
  git add script.sh

  run git commit -m "Add script"
  assert_success
  refute_output --partial "Made executable"
}

@test "modify_commit_message changes commit message content" {
  create_config '{
    "commit-msg": "modify_commit_message \"$1\" \"s/foo/bar/\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "This is foo"
  assert_success

  # Check that the commit message was modified
  run git log -1 --pretty=%B
  assert_output_contains "This is bar"
  refute_output --partial "This is foo"
}

@test "modify_commit_message handles multiple replacements" {
  create_config '{
    "commit-msg": "modify_commit_message \"$1\" \"s/test/prod/g\""
  }'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test: update test config"
  assert_success

  run git log -1 --pretty=%B
  assert_output_contains "prod: update prod config"
}

@test "applyTo filter works with shell scripts" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "echo Processing shell script: $FISHOOK_PATH",
      "applyTo": ["*.sh"]
    }]
  }'
  install_fishook

  stage_file "script.sh" "#!/bin/bash\necho test"
  stage_file "readme.md" "# README"

  run git commit -m "test commit"
  assert_success
  assert_output_contains "Processing shell script: script.sh"
  refute_output --partial "Processing shell script: readme.md"
}

@test "skipList filter excludes fishook config files" {
  create_config '{
    "pre-commit": [{
      "onFileEvent": "echo Processing: $FISHOOK_PATH",
      "skipList": ["*fishook*"]
    }]
  }'
  install_fishook

  stage_file "app.js" "console.log('test')"
  stage_file "fishook.local.json" "{}"

  run git commit -m "test commit"
  assert_success
  assert_output_contains "Processing: app.js"
  refute_output --partial "Processing: fishook.local.json"
}

@test "onAdd event runs for newly added files" {
  create_config '{
    "pre-commit": [{
      "onAdd": "echo New file added: $FISHOOK_PATH"
    }]
  }'
  install_fishook

  stage_file "newfile.txt" "new content"

  run git commit -m "Add new file"
  assert_success
  assert_output_contains "New file added: newfile.txt"
}

@test "onChange event runs for modified files" {
  create_config '{
    "pre-commit": [{
      "onChange": "echo File modified: $FISHOOK_PATH"
    }]
  }'
  install_fishook

  # Create and commit a file first
  echo "original" > existing.txt
  git add existing.txt
  git commit -m "Add existing file"

  # Now modify it
  echo "modified" > existing.txt
  git add existing.txt

  run git commit -m "Modify file"
  assert_success
  assert_output_contains "File modified: existing.txt"
}
