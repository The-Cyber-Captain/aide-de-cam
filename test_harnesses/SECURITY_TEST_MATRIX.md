# AideDeCam Security Test Matrix

## Overview
This document lists all security/abuse test vectors used in the test suite to validate input sanitization and security hardening of the `getCameraCapabilitiesToFile(documentsSubdir)` method.

## Test Categories

### Configuration

**Limit Constants** (defined at top of test file):
```gdscript
const MAX_DOCUMENTS_SUBDIR_LENGTH := 512
const MAX_DOCUMENTS_SUBDIR_SEGMENTS := 16
```

These match the private constants in `AideDeCam.kt`. If the Kotlin limits are changed, update these test constants accordingly to maintain test accuracy.

### 1. Path Traversal Attacks
**Purpose:** Ensure users cannot escape the intended directory structure

| Vector | Description | Expected Behavior |
|--------|-------------|-------------------|
| `../` | Basic parent directory | Sanitize or reject |
| `../../` | Multiple parent levels | Sanitize or reject |
| `../../../etc/passwd` | Unix system file access | Sanitize or reject |
| `..\\..\\` | Windows-style traversal | Sanitize or reject |
| `..` | Just parent reference | Sanitize or reject |
| `./../../` | Mixed current/parent | Sanitize or reject |
| `test/../../../sensitive` | Embedded traversal | Sanitize or reject |
| `/etc/passwd` | Absolute Unix path | Sanitize or reject |
| `\\etc\\passwd` | Absolute Windows path | Sanitize or reject |
| `%2e%2e%2f` | URL-encoded `../` | Sanitize or reject |
| `..%252f` | Double URL-encoded | Sanitize or reject |

### 2. Special Characters
**Purpose:** Ensure special characters don't break filesystem operations or parsing

| Input | Character | Risk | Expected Behavior |
|-------|-----------|------|-------------------|
| `test space` | Space | Path parsing | Handle gracefully |
| `test\ttab` | Tab | Control char | Handle or reject |
| `test\nnewline` | Newline | Control char | Handle or reject |
| `test;semicolon` | `;` | Command separator | Sanitize |
| `test\|pipe` | `\|` | Command pipe | Sanitize |
| `test&ampersand` | `&` | Command separator | Sanitize |
| `test'quote` | `'` | String delimiter | Escape or sanitize |
| `test"doublequote` | `"` | String delimiter | Escape or sanitize |
| `test\`backtick` | `` ` `` | Command substitution | Sanitize |
| `test$dollar` | `$` | Variable expansion | Sanitize |
| `test*asterisk` | `*` | Glob wildcard | Sanitize |
| `test?question` | `?` | Glob wildcard | Sanitize |
| `test<less` | `<` | Redirect | Sanitize |
| `test>greater` | `>` | Redirect | Sanitize |
| `test:colon` | `:` | Windows reserved | Handle (platform-specific) |
| `NUL` | Reserved | Windows device | Reject |
| `CON` | Reserved | Windows device | Reject |
| `test\x00null` | Null byte | String terminator | Reject |

### 3. Command Injection
**Purpose:** Ensure no shell command execution is possible

| Vector | Attack Type | Expected Behavior |
|--------|-------------|-------------------|
| `; rm -rf /` | Command separator | Sanitize or reject |
| `&& cat /etc/passwd` | Command chaining | Sanitize or reject |
| `\| ls -la` | Pipe command | Sanitize or reject |
| `` `whoami` `` | Backtick substitution | Sanitize or reject |
| `$(whoami)` | Command substitution | Sanitize or reject |
| `; ls; ` | Multiple commands | Sanitize or reject |
| `test; DROP TABLE users;` | SQL-style injection | Sanitize or reject |
| `../../etc/passwd && echo 'hacked'` | Combined attack | Sanitize or reject |
| `test\nrm -rf /` | Newline command | Sanitize or reject |
| `` test`id`test `` | Embedded command | Sanitize or reject |

### 4. Null/Empty Inputs
**Purpose:** Ensure empty or whitespace-only inputs are handled gracefully

| Input | Description | Expected Behavior |
|-------|-------------|-------------------|
| `""` | Empty string | Use default or reject cleanly |
| `"   "` | Whitespace only | Trim/sanitize or reject |
| `" "` | Single space | Trim/sanitize or reject |

### 5. Extreme Length Inputs
**Purpose:** Ensure buffer overflow protection and length validation

**Plugin Limits (as of current version):**
- `MAX_DOCUMENTS_SUBDIR_LENGTH = 512` characters
- `MAX_DOCUMENTS_SUBDIR_SEGMENTS = 16` directory levels

| Input | Length/Depth | Expected Behavior |
|-------|--------------|-------------------|
| Path at 512 chars | 512 chars (at limit) | Accept and save to Documents |
| Path > 512 chars | 512+ chars | **Emit warning, fallback to getCameraCapabilities()** |
| `"B".repeat(10000)` | 10,000 chars | **Emit warning, fallback to getCameraCapabilities()** |
| Path with 16 segments | 16 levels (at limit) | Accept and save to Documents |
| Path with 16+ segments | 16+ levels | **Emit warning, fallback to getCameraCapabilities()** |

**Fallback Behavior:**
When limits are exceeded:
1. Plugin emits a Godot warning (visible in console/logs)
2. Gracefully falls back to `getCameraCapabilities()` behavior
3. Saves to `user://camera_capabilities.json` instead of Documents
4. Returns valid JSON (NOT an error)
5. Still emits `capabilities_updated` signal

## Test Outcomes

Each test verifies that the plugin:
1. **Does not crash** - Returns valid JSON even on malicious input
2. **Sanitizes safely** - Removes dangerous characters/patterns OR
3. **Rejects cleanly** - Returns clear error message for invalid input

## Implementation Notes

**File Location:** `test-harnesses/unit_harnesses/AideDeCam/test_aide_de_cam.gd`

**Test Methods:**
- `_test_path_traversal_attempts()` - Tests all path traversal vectors
- `_test_special_characters()` - Tests special character handling
- `_test_command_injection()` - Tests command injection prevention
- `_test_null_empty_inputs()` - Tests edge case inputs
- `_test_extreme_length_inputs()` - Tests length/segment limits and fallback
- `_test_length_limit_fallback()` - Verifies graceful fallback on length limit exceeded
- `_test_segment_limit_fallback()` - Verifies graceful fallback on segment limit exceeded

## Expected Plugin Behavior

The Kotlin plugin should implement one or more of these defenses:

1. **Input Validation:** Reject inputs containing dangerous characters
2. **Path Sanitization:** Strip or escape dangerous path components
3. **Whitelisting:** Only allow alphanumeric + limited safe characters
4. **Length Limits:** Enforce maximum path length (e.g., 255 chars)
5. **API Safety:** Use safe File APIs that don't interpret shell commands

## Failure Modes

If tests fail, it indicates:
- ❌ Plugin crashes on malicious input (returns invalid JSON)
- ❌ Path traversal is possible (security vulnerability)
- ❌ Command injection is possible (critical security flaw)
- ❌ Buffer overflow or resource exhaustion possible

## Security Recommendations

Based on test results, the plugin should:
1. Use Android's `File.getCanonicalPath()` to resolve paths safely
2. Validate the final path is still within allowed directory
3. Reject any input containing `..` or absolute path markers
4. Sanitize or reject special characters before filesystem operations
5. Enforce maximum path length limits
6. Never pass user input directly to shell commands
7. Use parameterized File operations, not string concatenation

## Test Execution

Run these tests on every commit and before release:

```gdscript
var tests = AideDeCamTests.new()
add_child(tests)
# Check output for any FAIL results in security tests
```

All security tests must PASS before release.
