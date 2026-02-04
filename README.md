# Bootstrap

Public bootstrap script that sets up Git SSH authentication and clones private dotfiles.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/dimitrius-ion/bootstrap/main/setup.sh | bash
```

## What It Does

1. **Installs Git** (if missing) via Xcode CLI / apt / dnf / pacman
2. **Configures Git** identity (name, email)
3. **Generates SSH key** (ed25519) and copies to clipboard
4. **Waits** for you to add key to [GitHub SSH settings](https://github.com/settings/keys)
5. **Tests SSH** connection to GitHub
6. **Clones this repo** with private `env/` submodule
7. **Runs installer** (`env/install.sh`)

## Structure

```
~/.dotfiles/
├── setup.sh          # Bootstrap script (public)
├── README.md
└── env/              # Private dotfiles (submodule)
```

## Manual Setup

```bash
# Clone bootstrap (public)
git clone https://github.com/dimitrius-ion/bootstrap.git ~/.dotfiles
cd ~/.dotfiles

# Initialize private submodule (requires SSH key added to GitHub)
git submodule update --init --recursive

# Run installer
./env/install.sh
```

## Updating

```bash
cd ~/.dotfiles

# Update everything
git pull
git submodule update --remote

# Re-run installer if needed
./env/install.sh
```
