# Release v{VERSION}

## 🚀 What's New

-

## 🐛 Bug Fixes

-

## 🔧 Improvements

-

## 📚 Documentation

-

## 🧪 Testing

-

## 🛠️ Scripts Included

- **db-backup-restore**: v{VERSION} - PostgreSQL backup and restore with compression and validation
- **db-copy**: v{VERSION} - Database copying and cloning with filtering options
- **db-user-manager**: v{VERSION} - User and permission management system

## 📋 Installation

### Quick Install

```bash
# Download and extract
curl -L https://github.com/hongkongkiwi/db-helper-scripts/releases/download/v{VERSION}/db-helper-scripts-{VERSION}.tar.gz \
  | tar -xz

# Run installer
cd db-helper-scripts-{VERSION}
./install.sh
```

### Manual Install

```bash
# Download scripts directly
curl -O https://github.com/hongkongkiwi/db-helper-scripts/releases/download/v{VERSION}/db-backup-restore
curl -O https://github.com/hongkongkiwi/db-helper-scripts/releases/download/v{VERSION}/db-copy
curl -O https://github.com/hongkongkiwi/db-helper-scripts/releases/download/v{VERSION}/db-user-manager

# Make executable and move to PATH
chmod +x db-*
sudo mv db-* /usr/local/bin/
```

## 📦 Files in this Release

- `db-helper-scripts-{VERSION}.tar.gz` - Complete package with all scripts and tests
- `db-helper-scripts-{VERSION}.zip` - Complete package in ZIP format

## 🔍 Verification

```bash
# Verify installation
db-backup-restore version
db-copy version
db-user-manager version

# Run basic tests
db-backup-restore help
db-copy help
db-user-manager help
```

## 📖 Documentation

Full documentation is available in the
[README.md](https://github.com/hongkongkiwi/db-helper-scripts/blob/main/README.md).

## 🤝 Support

- 📋 [Issues](https://github.com/hongkongkiwi/db-helper-scripts/issues)
- 💬 [Discussions](https://github.com/hongkongkiwi/db-helper-scripts/discussions)
- 📧 Contact: [Your contact information]

---

**Full Changelog**:
<https://github.com/hongkongkiwi/db-helper-scripts/compare/v{PREVIOUS_VERSION}...v{VERSION}>
