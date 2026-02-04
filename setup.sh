#!/usr/bin/env bash
# Bootstrap script - sets up Git SSH auth, then clones dotfiles with private submodule
# Usage: curl -fsSL https://raw.githubusercontent.com/dimitrius-ion/dotfiles/main/setup.sh | bash

set -e

BOOTSTRAP_REPO="https://github.com/dimitrius-ion/dotfiles.git"
PRIVATE_REPO="git@github.com:dimitrius-ion/env.git"
DOTFILES_DIR="$HOME/.dotfiles"

info() { printf "\033[0;34m[INFO]\033[0m %s\n" "$1"; }
success() { printf "\033[0;32m[OK]\033[0m %s\n" "$1"; }
warn() { printf "\033[0;33m[WARN]\033[0m %s\n" "$1"; }

echo ""
echo "╔══════════════════════════════════════╗"
echo "║       Environment Bootstrap          ║"
echo "╚══════════════════════════════════════╝"
echo ""

# =============================================================================
# 1. Check/Install Git
# =============================================================================
if ! command -v git &> /dev/null; then
    warn "Git not found"
    OS="$(uname -s)"
    if [ "$OS" = "Darwin" ]; then
        info "Installing Xcode Command Line Tools..."
        xcode-select --install 2>/dev/null || true
        info "Press Enter after installation completes"
        read -r
    elif [ "$OS" = "Linux" ]; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y git
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y git
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm git
        fi
    fi
fi
success "Git installed: $(git --version)"

# =============================================================================
# 2. Configure Git identity
# =============================================================================
echo ""
if [ -z "$(git config --global user.name)" ]; then
    read -p "Enter your Git name: " git_name
    git config --global user.name "$git_name"
fi
if [ -z "$(git config --global user.email)" ]; then
    read -p "Enter your Git email: " git_email
    git config --global user.email "$git_email"
fi
success "Git identity: $(git config --global user.name) <$(git config --global user.email)>"

# =============================================================================
# 3. Setup SSH key for GitHub
# =============================================================================
echo ""
info "Testing GitHub SSH connection..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    success "GitHub SSH authentication working"
else
    warn "GitHub SSH authentication failed"
    SSH_KEY="$HOME/.ssh/id_ed25519"

    if [ ! -f "$SSH_KEY" ]; then
        info "Generating SSH key..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -C "$(git config --global user.email)" -f "$SSH_KEY" -N ""
        success "SSH key generated"
    fi

    # Start ssh-agent and add key
    eval "$(ssh-agent -s)" > /dev/null 2>&1
    ssh-add "$SSH_KEY" 2>/dev/null || true

    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "Add this SSH key to GitHub → Settings → SSH Keys:"
    echo "https://github.com/settings/keys"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    cat "$SSH_KEY.pub"
    echo ""
    echo "════════════════════════════════════════════════════════════════"

    # Copy to clipboard if possible
    if command -v pbcopy &> /dev/null; then
        cat "$SSH_KEY.pub" | pbcopy
        info "SSH key copied to clipboard (macOS)"
    elif command -v xclip &> /dev/null; then
        cat "$SSH_KEY.pub" | xclip -selection clipboard
        info "SSH key copied to clipboard (Linux)"
    elif command -v wl-copy &> /dev/null; then
        cat "$SSH_KEY.pub" | wl-copy
        info "SSH key copied to clipboard (Wayland)"
    fi

    echo ""
    read -p "Press Enter after adding the key to GitHub..."

    # Verify SSH after setup
    info "Testing GitHub SSH connection..."
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        success "GitHub SSH authentication working"
    else
        warn "SSH test returned unexpected response (this may be OK)"
    fi
fi

# =============================================================================
# 5. Clone bootstrap repo with private submodule
# =============================================================================
echo ""
if [ -d "$DOTFILES_DIR" ]; then
    warn "Dotfiles directory already exists: $DOTFILES_DIR"
    read -p "Remove and re-clone? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$DOTFILES_DIR"
    else
        info "Skipping clone"
        exit 0
    fi
fi

info "Cloning dotfiles..."
mkdir -p "$(dirname "$DOTFILES_DIR")"
git clone "$BOOTSTRAP_REPO" "$DOTFILES_DIR"
success "Bootstrap repo cloned"

# Initialize private submodule
info "Initializing private dotfiles submodule..."
cd "$DOTFILES_DIR"
git submodule update --init --recursive
success "Private dotfiles loaded"

# =============================================================================
# 6. Run dotfiles installer
# =============================================================================
echo ""
read -p "Run dotfiles installer now? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    ./env/install.sh
fi

echo ""
success "Bootstrap complete!"
info "Dotfiles installed at: $DOTFILES_DIR"
