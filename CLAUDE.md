# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Architecture

Two-repo dotfiles system for **Omarchy** (Arch Linux + Hyprland): a **public bootstrap** repo (this root) and a **private `env/` submodule** containing all actual configurations.

```
~/.dotfiles/
├── setup.sh              # Bootstrap: installs Git, SSH key, clones repo
├── AGENTS.md             # AI agent guidance
└── env/                  # Private submodule (git@github.com:dimitrius-ion/env.git)
    ├── install.sh        # Symlink installer with backup to ~/.dotfiles_backup/
    ├── uninstall.sh      # Removes symlinks
    ├── fish/             # Fish shell config
    ├── nvim/             # Neovim config (LazyVim extension)
    ├── git/              # Git config + global gitignore
    ├── ghostty/          # Terminal emulator config
    ├── hypr/             # Hyprland compositor (bindings, monitors, themes)
    ├── waybar/           # Status bar (config.jsonc + style.css)
    ├── omarchy/          # Omarchy customizations (themes, hooks, extensions)
    ├── btop/             # System monitor config
    ├── fastfetch/        # System info display config
    ├── system/           # System scripts, udev rules, power management
    └── systemd/          # User systemd services (battery, rclone, sleep hooks)
```

## Commands

```bash
# Install/update all symlinks (backs up existing files first)
./env/install.sh

# Auto-confirm prompts
./env/install.sh --yes

# Remove all symlinks
./env/uninstall.sh

# Update submodule to latest
git submodule update --remote
```

No build process, linter, or tests. Validation is manual.

## Symlink Strategy

- **Individual file linking**: Fish `conf.d/` and `functions/` (preserves existing files)
- **Whole-directory linking**: Neovim (`nvim/` → `~/.config/nvim`)
- **Individual .conf linking**: Hyprland files (coexists with Omarchy defaults)
- **Direct file linking**: Git (`gitconfig` → `~/.gitconfig`), Ghostty
- **Whole-directory linking**: Omarchy themes (`themes/nes/` → `~/.config/omarchy/themes/nes`)
- **Individual file linking**: Omarchy hooks, btop, fastfetch

## Neovim Architecture (`env/nvim/`)

Extends **LazyVim** (omarchy-nvim's framework). Load order follows LazyVim convention:
1. `init.lua` — Just `require("config.lazy")`
2. `lua/config/lazy.lua` — LazyVim bootstrap (imports `lazyvim.plugins` + `plugins`)
3. `lua/config/options.lua` — Custom options (4-space tabs, relativenumber, ripgrep grepprg)
4. `lua/config/keymaps.lua` — Custom keymaps (unique to us, LazyVim-provided ones removed)
5. `lua/config/autocmds.lua` — Custom autocmds (large-file handling, cursorline)

Plugin specs in `lua/plugins/` (LazyVim convention):
- `overrides.lua` — Disable neo-tree (use Oil), configure LSP servers, treesitter parsers
- `omarchy.lua` — Theme hotreload, all-themes, disable news, disable scroll animations
- `copilot.lua` — GitHub Copilot via cmp integration
- `obsidian.lua` — Note-taking vault integration
- `oil.lua` — File browser (`<BS>` to open)
- `harpoon.lua` — Quick file navigation
- `git.lua` — Fugitive (gitsigns provided by LazyVim)
- `csv.lua`, `undotree.lua` — Utilities

Custom plugins in `plugin/`:
- `floaterminal.lua` — Floating terminal (`<leader>t`) + OpenCode integration
- `menu.lua` — Right-click context menu
- `ws.lua` — `:Ws` workspace sync command
- `after/transparency.lua` — Transparent background for all highlight groups

Theme symlink: `lua/plugins/theme.lua` → `~/.config/omarchy/current/theme/neovim.lua` (created by install.sh)

**Key keybinding prefixes (Leader = Space):**
- `<leader>f` find (LazyVim Telescope)
- `<leader>g` git (Fugitive)
- `<leader>x` diagnostics (LazyVim Trouble)
- `<leader>o` Obsidian notes
- `<leader>r` ripgrep
- `<leader>t` floating terminal
- `<BS>` Oil file browser

## Hyprland Architecture (`env/hypr/`)

Extends Omarchy defaults by linking individual `.conf` files rather than replacing the whole directory. Key files:
- `bindings.conf` — Vim-style window navigation (h/j/k/l)
- `monitors.conf` — Multi-monitor setup with hotplug handling
- `autostart.conf` — Extra autostart processes (monitor handler, background)
- `scripts/` — Lid close/open, monitor handler, mirror toggle
- `theme/` — Extended theme (hyprland.conf, hyprlock.conf, waybar.css, mako.ini, background)

## Omarchy Customizations (`env/omarchy/`)

- `themes/nes/` — Custom NES theme (backgrounds, color configs for all apps)
- `hooks/` — Sample hooks for theme-set, font-set, post-update events
- `extensions/menu.sh` — Custom Omarchy menu overrides

## Fish Shell (`env/fish/`)

- `config.fish` — Main config with env vars, aliases, helper functions (Arch Linux only)
- `conf.d/` — Auto-sourced init files (Deno, Rust)
- `functions/` — Custom functions including `bass` for Bash interop

Key functions: `v` (neovim), `load_secrets` (Proton Pass CLI), `load_env` (source .env), `history_fzf`.

## Notifications

Uses **Mako** (Omarchy default). Custom config at `env/hypr/theme/mako.ini` extends `~/.local/share/omarchy/default/mako/core.ini`.

## Code Style

### Lua (Neovim)
- 4-space indentation
- `vim.opt` for options, `vim.keymap.set()` for keybindings with descriptive `desc` field
- Plugin specs return a table or list of tables
- Override LazyVim plugins by re-specifying them with `opts` or `enabled = false`

### Fish
- `if test` over brackets; `command -v` for existence checks
- PATH: use `fish_add_path` (idempotent)
- Secrets: `load_secrets` via Proton Pass CLI, never hardcode

### Bash
- Shebang: `#!/usr/bin/env bash` with `set -e` and `set -o pipefail`
- 2-space indentation, quote all variables
- Logging: `info()`, `success()`, `warn()`, `error()` with ANSI colors
- Package management: `pacman` only (Arch Linux)

## Key Conventions

- **Arch Linux only**: No macOS/cross-platform code
- **Omarchy pattern**: Override in `~/.config/`, never modify `~/.local/share/omarchy/`
- **No hardcoded secrets**: Use Proton Pass CLI, env vars, or `.env` files
- **Large file handling**: TreeSitter disabled on files >1MB
- **Configurable paths**: Use env vars (e.g., `OBSIDIAN_VAULT`) for user-specific paths
- **Git workflow**: `pull.rebase = true`, `push.autoSetupRemote = true`, common aliases: `st`, `co`, `br`, `ci`, `lg`
