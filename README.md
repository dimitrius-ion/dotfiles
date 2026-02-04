# Bootstrap

Public bootstrap script that sets up Git SSH authentication and clones private dotfiles.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/dimitrius-ion/dotfiles/main/setup.sh | bash
```

## What It Does

1. **Installs Git** (if missing) via Xcode CLI / apt / dnf / pacman
2. **Configures Git** identity (name, email)
3. **Tests SSH** — skips to step 6 if already authenticated
4. **Generates SSH key** (ed25519) and copies to clipboard
5. **Waits** for you to add key to [GitHub SSH settings](https://github.com/settings/keys)
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
git clone https://github.com/dimitrius-ion/dotfiles.git ~/.dotfiles
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
