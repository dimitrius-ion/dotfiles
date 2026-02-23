# AGENTS.md

Guidance for agentic coding systems working in this dotfiles repository.

## Repository Overview

Cross-platform (macOS/Linux) dotfiles containing configurations for:
- **Fish shell** - Shell configuration with environment setup
- **Neovim** - Lua configuration with plugins and LSP
- **Git** - Global Git configuration
- **Ghostty** - Terminal emulator settings


## Build / Setup Commands

No build process or tests. Configuration validation is manual:

```bash
# Install symlinks to system directories
./env/install.sh

# Dry-run or revert
./env/install.sh --yes        # Auto-confirm prompts
```

**Key paths after install:**
- Fish: `env/fish/` → `~/.config/fish/`
- Neovim: `env/nvim/` → `~/.config/nvim/`
- Git: `env/git/gitconfig` → `~/.gitconfig`

## Code Structure

### Lua (Neovim Configuration)

**Location:** `env/nvim/lua/`

**Load order in `init.lua`:**
1. `config/options.lua` - Vim settings (4-space tabs, relative line numbers)
2. `config/keymaps.lua` - 130+ keybindings
3. `config/lazy.lua` - Plugin manager bootstrap
4. `config/appearance.lua` - Tokyo Night theme
5. `config/autocmds.lua` - Autocommands
6. `config/plugins/*.lua` - Plugin configurations

**Key directories:**
- `lua/config/` - Core settings
- `lua/config/plugins/` - Plugin specs (LSP, completion, telescope, etc.)
- `lua/plugin/` - Custom plugins (floaterminal, menu)

### Fish Shell

**Location:** `env/fish/`

**Structure:**
- `config.fish` - Main config with env vars, aliases, custom functions
- `conf.d/` - Auto-sourced init files (Deno, Rust, etc.)
- `functions/` - Custom shell functions

### Bash Shell Scripts

**Location:** Root and `env/`

- `setup.sh` - Bootstrap script for Git SSH setup
- `env/install.sh` - Installation/symlink manager

## Code Style Guidelines

### Lua (Neovim)

**Formatting:**
- 4-space indentation (set in `options.lua`)
- Use `vim.opt` for options, `vim.keymap.set()` for keybindings
- Use `vim.api.nvim_*` for Neovim API calls
- Lazy-load plugins with `lazy=true` or event triggers

**Naming:**
- Local variables: `snake_case`
- Plugin modules: return table with config spec
- Keymaps: descriptive `desc` field always provided
- Functions: descriptive names, prefix with `on_` for callbacks

**LSP & Plugins:**
- Use `pcall(require, 'module')` for optional dependencies with fallbacks
- Plugin specs return a table or list of tables
- Keep plugin-specific config in `lua/config/plugins/` directory

**Error Handling:**
```lua
local ok, module = pcall(require, 'telescope.builtin')
if ok then
  -- Use module
else
  -- Fallback
end
```

### Fish Shell

**Formatting:**
- Indentation: spaces (4 or 2 conventional)
- Comments: `#` with one space after
- Functions: use `function` keyword, end with `end`
- Conditions: prefer `if test` over brackets

**Naming:**
- Functions/aliases: `snake_case` or `camelCase`
- Environment variables: `SCREAMING_SNAKE_CASE`
- Private helpers: prefix with `_`

**Key Patterns:**
- OS detection: `$IS_MACOS` (1/0) and `$IS_LINUX` (1/0)
- PATH management: use `fish_add_path` (idempotent, no duplicates)
- Secrets: load via `load_secrets` (Proton Pass CLI), never hardcode
- Env files: use `load_env` function to source `.env`

**Error Handling:**
```fish
if command -v command_name &> /dev/null
  # Command exists
else
  # Fallback or error
end

if test -f $file
  # File exists
end
```

### Bash Shell Scripts

**Formatting:**
- Shebang: `#!/usr/bin/env bash`
- Set options: `set -e` (exit on error), `set -o pipefail`
- 2-space indentation
- Quote all variables: `"$var"` not `$var`

**Naming:**
- Functions: `snake_case`
- Private functions: prefix with `_`
- Constants: `SCREAMING_SNAKE_CASE`

**Error Handling:**
```bash
set -e  # Exit on error
set -o pipefail  # Fail on pipe errors

if [ -f "$file" ]; then
  # Do something
fi

if command -v cmd &> /dev/null; then
  # Command exists
fi
```

**Logging Functions:**
```bash
info() { printf "\033[0;34m[INFO]\033[0m %s\n" "$1"; }
success() { printf "\033[0;32m[OK]\033[0m %s\n" "$1"; }
warn() { printf "\033[0;33m[WARN]\033[0m %s\n" "$1"; }
error() { printf "\033[0;31m[ERROR]\033[0m %s\n" "$1"; }
```

## Important Conventions

- **Cross-platform:** Detect OS with `$IS_MACOS`/`$IS_LINUX` (Fish) or `uname` (Bash)
- **No hardcoded secrets:** Use Proton Pass CLI, environment variables, or `.env` files
- **Large files:** TreeSitter disabled on files >1MB in `options.lua`
- **Lazy loading:** Plugins use `lazy=true` or event triggers to speed up startup
- **Configurable paths:** Use env vars (e.g., `OBSIDIAN_VAULT`) for user-specific paths

## Git Workflow

- Rebasing enabled: `pull.rebase = true`
- Auto-setup upstream: `push.autoSetupRemote = true`
- Common aliases: `st`, `co`, `br`, `ci`, `lg`
- Uses Neovim as editor: `core.editor = nvim`

## Related Documentation

- **CLAUDE.md** (`env/CLAUDE.md`) - Detailed architecture and keybindings
- **README.md** - Quick start and overview
