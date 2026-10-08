# Changelog

## Unreleased

## [1.2.0] - 2026-10-07

### Added
- Added a runnable CLI smoke test to the CI workflow.
- Documented local CLI installation, usage, vault permissions, encryption, and shell-history considerations.
- Added `--version` output.
- Added CODEOWNERS, security reporting guidance, and weekly Dependabot updates for npm and GitHub Actions.

### Changed
- Made vault configuration updates atomic and restricted vault files to owner-only permissions.
- Passed secret keys and metadata as data instead of interpolating them into Python source.
- Made exported shell commands quote secret keys and reject invalid environment variable names.
- Upgraded the scan-report artifact action to `actions/upload-artifact@v7`.

### Fixed
- Return clear errors for missing secrets and incomplete vaults; allow help/version commands before vault initialization.
- Validate argument counts for `set` and `get`.
