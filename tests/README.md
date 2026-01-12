# Fishook Test Suite

BATS-based test suite for the fishook git hook runner.

## Running Tests

```bash
# Run all tests
npm test

# Run specific test files
npm run test:install      # Installation/uninstallation tests
npm run test:integration  # Integration tests
npm run test:helpers      # Helper utility tests
```

## Test Structure

```
tests/
├── README.md              # This file
├── helpers.bash           # Shared test helpers and setup functions
├── test_install.bats      # Tests for install/uninstall functionality
├── test_integration.bats  # End-to-end integration tests
├── test_helpers.bats      # Tests for common/* helper utilities
└── fixtures/              # Test fixtures and sample configs
    └── configs/           # Sample fishook.json configurations
```

## How Tests Work

Each test runs in an isolated temporary git repository:
1. `setup_temp_repo()` creates a fresh git repo in a temp directory
2. Copies `fishook.sh` and `common/` into the test repo
3. Tests can install hooks and commit files
4. `teardown_temp_repo()` cleans up after each test

## Helper Functions

Available in `helpers.bash`:

- **setup_temp_repo()** - Create isolated git repo for testing
- **teardown_temp_repo()** - Clean up temp repo
- **install_fishook()** - Install hooks in current test repo
- **uninstall_fishook()** - Remove hooks
- **create_config(json)** - Create fishook.json with given content
- **run_fishook_hook(name, args...)** - Run a specific hook
- **stage_file(filename, content)** - Create and stage a file
- **assert_hook_installed(hook_name)** - Verify hook file exists and is executable
- **assert_hook_not_installed(hook_name)** - Verify hook doesn't exist
- **assert_output_contains(text)** - Check command output contains text

## Test Coverage

### Installation Tests (test_install.bats)
- ✅ Installing configured hooks
- ✅ Uninstalling hooks
- ✅ Installing without config
- ✅ Overwriting existing hooks (option 1)
- ✅ Chaining existing hooks (option 2)
- ✅ Backing up existing hooks (option 3)
- ✅ Verifying installed hooks reference fishook.sh

### Integration Tests (test_integration.bats)
- ✅ Running simple hooks
- ✅ Hooks that fail and block commits
- ✅ Post-commit hooks
- ✅ Multiple commands in sequence
- ✅ Object format with "run" property
- ✅ File events (onFileEvent, onAdd, onChange)
- ✅ Filters (applyTo, skipList)
- ✅ Dry-run mode (prevents command execution)
- ✅ List and explain commands

### Helper Utility Tests (test_helpers.bats)
- ✅ forbid_pattern - blocking forbidden patterns
- ✅ forbid_pattern - regex support
- ✅ ensure_executable - making scripts executable
- ✅ modify_commit_message - editing commit messages
- ✅ File filters with applyTo and skipList
- ✅ Event handlers (onAdd, onChange)

## Adding New Tests

1. Create a new `.bats` file or add to existing ones
2. Use the standard structure:
```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_temp_repo
}

teardown() {
  teardown_temp_repo
}

@test "description of test" {
  create_config '{"pre-commit": "echo test"}'
  install_fishook

  stage_file "test.txt"

  run git commit -m "test"
  assert_success
  assert_output_contains "test"
}
```

## Dependencies

- **bats** - Bash Automated Testing System
- **bats-support** - Supporting library for assertions
- **bats-assert** - Assertion helpers

## Environment Variables for Testing

**FISHOOK_INSTALL_CHOICE** - Bypass interactive prompts during install
- Set to `1` for overwrite existing hooks
- Set to `2` for chain existing hooks
- Set to `3` for backup existing hooks

Example:
```bash
FISHOOK_INSTALL_CHOICE=1 ./fishook.sh install
```

This is useful for automated testing and CI/CD scenarios where interactive input isn't possible.

## Notes

- Tests run in isolated temporary directories
- Each test gets a fresh git repository
- Git is configured with test user name/email
- GPG signing is disabled for test commits
- Tests clean up after themselves automatically
- Non-interactive install mode is used for testing existing hook scenarios
