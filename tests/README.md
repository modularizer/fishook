# Fishook Test Suite

BATS-based test suite for the fishook git hook runner.

## Running Tests

```bash
# Run all tests (109 tests)
npm test

# Run specific test files
npm run test:install      # Installation/uninstallation tests (8 tests)
npm run test:integration  # Integration tests (12 tests)
npm run test:helpers      # Helper utility tests (11 tests)
npm run test:common       # Common utilities tests (15 tests)
npm run test:hooks        # Various git hooks tests (23 tests)
npm run test:env          # Arguments and environment tests (40 tests)
```

## Test Structure

```
tests/
├── README.md               # This file
├── helpers.bash            # Shared test helpers and setup functions
├── test_install.bats       # Tests for install/uninstall functionality
├── test_integration.bats   # End-to-end integration tests
├── test_helpers.bats       # Tests for common/* helper utilities
├── test_common_utils.bats  # Tests for all common/ utilities (forbid-file-pattern, pcsed, etc.)
├── test_various_hooks.bats # Tests for various git hooks (commit-msg, post-commit, pre-push, etc.)
├── test_args_and_env.bats  # Tests for hook arguments and environment variables
└── fixtures/               # Test fixtures and sample configs
    └── configs/            # Sample fishook.json configurations
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

### Installation Tests (test_install.bats) - 8 tests
- ✅ Installing configured hooks
- ✅ Uninstalling hooks
- ✅ Installing without config
- ✅ Overwriting existing hooks (option 1)
- ✅ Chaining existing hooks (option 2)
- ✅ Backing up existing hooks (option 3)
- ✅ Verifying installed hooks reference fishook.sh

### Integration Tests (test_integration.bats) - 12 tests
- ✅ Running simple hooks
- ✅ Hooks that fail and block commits
- ✅ Post-commit hooks
- ✅ Multiple commands in sequence
- ✅ Object format with "run" property
- ✅ File events (onFileEvent, onAdd, onChange)
- ✅ Filters (applyTo, skipList)
- ✅ Dry-run mode (prevents command execution)
- ✅ List and explain commands

### Helper Utility Tests (test_helpers.bats) - 11 tests
- ✅ forbid_pattern - blocking forbidden patterns
- ✅ forbid_pattern - regex support
- ✅ ensure_executable - making scripts executable
- ✅ modify_commit_message - editing commit messages
- ✅ File filters with applyTo and skipList
- ✅ Event handlers (onAdd, onChange)

### Common Utilities Tests (test_common_utils.bats) - 15 tests
- ✅ forbid_file_pattern - blocking files by name pattern
- ✅ forbid_file_pattern - regex patterns for filenames
- ✅ pcsed - applying sed transformations to staged content
- ✅ pcsed --index-only - modifying only staged content
- ✅ pcsed - regex replacements
- ✅ scope.sh helpers - new(), old(), diff() functions
- ✅ raise() function for custom error messages
- ✅ Multiple utilities working together
- ✅ Utilities with filters (applyTo, skipList)

### Various Git Hooks Tests (test_various_hooks.bats) - 23 tests
- ✅ **commit-msg** - validating commit message format
- ✅ **commit-msg** - modifying commit messages
- ✅ **commit-msg** - receiving message file path
- ✅ **post-commit** - running after successful commit
- ✅ **post-commit** - cannot block commits
- ✅ **post-commit** - triggering notifications
- ✅ **post-checkout** - running after branch checkout
- ✅ **post-checkout** - receiving previous/new HEAD
- ✅ **post-checkout** - detecting branch vs file checkout
- ✅ **post-merge** - running after git merge
- ✅ **post-merge** - detecting squash merge
- ✅ **prepare-commit-msg** - modifying message before editor
- ✅ **prepare-commit-msg** - receiving message source
- ✅ **pre-push** - blocking push to protected branch
- ✅ **pre-push** - receiving remote name and URL
- ✅ **pre-push** - running tests before push
- ✅ **pre-rebase** - blocking rebase of certain branches
- ✅ Multiple hooks working in sequence
- ✅ Hooks sharing state via files
- ✅ Hooks accessing FISHOOK environment variables

### Hook Arguments & Environment Tests (test_args_and_env.bats) - 40 tests
- ✅ **Base environment variables** (12 tests)
  - FISHOOK_REPO_ROOT, FISHOOK_REPO_NAME, FISHOOK_HOOK
  - FISHOOK_COMMON, FISHOOK_CONFIG_PATH, FISHOOK_CONFIG_DIR
  - FISHOOK_GIT_DIR, FISHOOK_HOOKS_PATH, FISHOOK_CWD
  - FISHOOK_DRY_RUN, FISHOOK_ARGV0
- ✅ **File event variables** (7 tests)
  - FISHOOK_PATH, FISHOOK_ABS_PATH
  - FISHOOK_EVENT, FISHOOK_EVENT_KIND, FISHOOK_STATUS
- ✅ **Hook-specific arguments** (15 tests)
  - commit-msg: $1 = message file path
  - prepare-commit-msg: $1 = message file, $2 = source, $3 = SHA
  - post-checkout: $1 = prev HEAD, $2 = new HEAD, $3 = branch flag
  - pre-push: $1 = remote name, $2 = remote URL
  - post-merge: $1 = squash flag
  - FISHOOK_REMOTE_NAME, FISHOOK_REMOTE_URL
- ✅ **FISHOOK_ARGS** (2 tests)
  - Contains all hook arguments
  - Properly quoted for spaces
- ✅ **Legacy compatibility** (2 tests)
  - GIT_HOOK_KEY, GIT_HOOK_ARGS
- ✅ **Variable correctness** (2 tests)
  - Absolute paths, correct extensions
  - Multiple variables set simultaneously

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
