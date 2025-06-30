# Release Process

This document describes how to create a new release of the Database Helper Scripts.

## Overview

All scripts (`db-backup-restore`, `db-copy`, `db-user-manager`) share a centralized version managed through the
`./release` script. When you create a new release:

1. All script `SCRIPT_VERSION` variables are updated to the same version
2. The `VERSION` file is updated
3. A git tag is created (e.g., `v2.1.0`)
4. Changes are committed and pushed to the repository

## Usage

### Check Current Version

```bash
./release --current
```

This shows the current version from the `VERSION` file and the individual script versions.

### Preview a Release

```bash
./release 2.1.0 --dry-run
```

This shows what would happen during a release without making any changes.

### Create a Release

```bash
./release 2.1.0
```

This will:

1. Update all script versions to `2.1.0`
2. Update the `VERSION` file to `2.1.0`
3. Create a git commit with the changes
4. Create an annotated git tag `v2.1.0`
5. Push the commit and tag to the remote repository

### Force a Release

If you have uncommitted changes and want to release anyway:

```bash
./release 2.1.0 --force
```

## Version Format

Versions must follow semantic versioning: `X.Y.Z` or `X.Y.Z-suffix`

Examples:

- `2.1.0`
- `1.5.2`
- `2.0.0-beta`
- `1.0.0-rc1`

## Prerequisites

- Git repository with a configured remote named `origin`
- Clean working directory (or use `--force` to override)
- Proper git credentials for pushing

## Examples

```bash
# Check what version we're currently on
./release --current

# Preview what a release to 2.1.0 would do
./release 2.1.0 --dry-run

# Create a new release
./release 2.1.0

# Create a beta release
./release 2.1.0-beta

# Force a release even with uncommitted changes
./release 2.1.0 --force
```

## Script Behavior

### Version Management

- Each script maintains its own `SCRIPT_VERSION` variable
- During release, all scripts are updated to the same version
- The central `VERSION` file tracks the current release version

### Git Operations

- Creates a commit with message "Release version X.Y.Z"
- Creates an annotated tag `vX.Y.Z` with detailed information
- Pushes both the commit and tag to `origin`

### Safety Checks

- Validates version format
- Checks for uncommitted changes (unless `--force` is used)
- Verifies all version updates were successful before tagging
- Ensures we're in a git repository

## No Tests Required

The release process intentionally skips running tests to keep it fast and simple.

Tests should be run separately during development and CI/CD processes.
