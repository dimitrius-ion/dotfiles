# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository shape

This is a **two-repo dotfiles system** for Arch Linux + Omarchy:

- **`~/Personal/dotfiles`** (this repo, public) — just a bootstrap. Contains `setup.sh` (installs git, sets up GitHub SSH, clones this repo + the private submodule, runs the installer) and the `env/` submodule pointer. Almost nothing else lives here.
- **`env/`** (private submodule, `git@github.com:dimitrius-ion/env.git`) — the actual dotfiles: all configs, installer modules, and system files. **This is where nearly all work happens.**

Because `env/` is a submodule, changes there are committed in `env/` first, then the pointer is bumped in `~/Personal/dotfiles` (the recent commit log here is almost entirely `chore(env): Bump submodule ...`).

`env/` itself nests further submodules (see `env/.gitmodules`): `external/pi`, `external/agentmemory`, and a ZMK keyboard firmware repo.

## Common commands

```bash
# Full install (from ~/Personal/dotfiles)
./env/install.sh

# Installer flags (run from env/)
./install.sh -l                 # list discovered modules with priority/order/deps
./install.sh -m <name>          # run a single module (e.g. -m claude, -m symlinks)
./install.sh -a                 # run all modules including default-disabled ones
./install.sh -y                 # auto-confirm all prompts (CI/scripting)
./install.sh -p                 # sweep broken dotfiles symlinks only, then exit

./uninstall.sh                  # remove managed symlinks, units, system files

# Update everything
git pull && git submodule update --remote
```

There is no build/test/lint tooling — this is shell + config files. The closest thing to a test is `./install.sh -l` to verify module discovery and ordering.

## Repo location is not fixed

The checkout can live anywhere (currently `~/Personal/dotfiles`). Everything derives from `install.sh`'s own location, and the installer publishes that location as the symlink `~/.local/share/dotfiles` → repo root.

**Never hardcode the repo path.** Use `$DOTFILES_DIR` in shell; where an absolute path must be written into a file that the installer does not template — systemd `ExecStart`, data paths in fish functions — go through the canonical link (`%h/.local/share/dotfiles/env/...` in units, `~/.local/share/dotfiles/env/...` elsewhere). Grep for `Personal/dotfiles` before committing; there should be no hits outside docs.

Moving the checkout is therefore `mv` + `./env/install.sh`. The installer repoints the link, relinks managed files, re-runs opt-in modules recorded in `~/.local/state/dotfiles/installed-modules`, and sweeps symlinks whose target has vanished from the repo. Links that merely name an old location are reported and relinked, never deleted.

## Installer architecture (`env/install.sh`)

The installer is a **module runner**, not a monolithic script:

1. **Discovery** — scans `env/modules/*/`, each providing `module.sh` (logic) and `module.conf` (metadata: `name`, `priority`, `enabled_by_default`, `depends`).
2. **Ordering** — modules run in `priority` order (ascending), but `depends=` forces a topological sort via `visit_module`. Cyclic or unknown dependencies abort the install.
3. **Execution** — each `module.sh` is **sourced** (not executed) into the installer's shell, so it inherits helpers and shared arrays. Default-disabled modules (`enabled_by_default=false`, e.g. `pi`, `agentmemory`, `debloat`) run only with `-a` or an explicit `-m`.

Current priority order: `fish`(10) → `claude`/`dependencies`(20) → `proton`(30) → `symlinks`(40) → `system`(50) → ... → `debloat`(200).

### Shared helpers (`env/lib/common.sh`)

All modules rely on these — use them instead of raw `ln`/`cp`:

- `backup_and_link <src> <dest>` — the core symlink primitive. Backs up any existing real file to `~/.dotfiles_backup/<timestamp>/` (preserving relative path), replaces stale symlinks, records into the `LINKED`/`SKIPPED`/`FAILED` summary arrays.
- `sudo_install` / `sudo_install_exec <src> <dest> <desc>` — install a system file with sudo; prompts on first install, silently updates thereafter.
- `restore_omarchy_config <dest> <template>` — hands a file back to Omarchy's ownership when we stop managing it.
- `confirm <prompt>` — respects `-y`/`AUTO_YES`; `info`/`success`/`warn`/`error` — colored logging.

Every `module.sh` starts with a `# Sourced by install.sh — do not execute directly` comment. Do not add `#!/bin/bash` or run them standalone.

## Omarchy coexistence pattern

Omarchy owns many config files (`hypr/`, `omarchy/`, `ghostty/`, GTK theme CSS) and **rewrites them on updates/theme changes**. The dotfiles therefore **extend rather than replace**:

- Symlink individual files (not whole directories) into `~/.config/hypr/` so Omarchy keeps owning the directory.
- For files Omarchy regenerates, keep our changes in a separate override file and **idempotently append an include** to Omarchy's file — `config-file = ...overrides` (ghostty) or `@import "geary-overrides.css"` (GTK) — or, where the format has no include mechanism, `jq -s '.[0] * .[1]'` merge (the quickshell bar's `omarchy/shell.json`).
- See `env/modules/symlinks/module.sh` for all of these; it's the reference for the extend-don't-replace approach.

Omarchy's own defaults also load *before* our config, and what they cover shifts between releases — 4.0 moved app/web-app keybindings into `default/hypr/bindings/applications.lua`, so re-declaring one leaves two binds firing on the same combo. After an Omarchy upgrade, check with:

```bash
hyprctl binds -j | jq 'map(select(.key != "")) | group_by([.modmask,.key]) | map(select(length > 1))'
```

**Danger: `omarchy-refresh-hyprland` / `omarchy-refresh-config hypr/*.lua` destroys these files.** Unlike `hyprland.conf`/`hyprland.lua` (deliberately left to Omarchy, restored via `restore_omarchy_config`), `config/hypr/{autostart,bindings,input,looknfeel,monitors}.lua` are symlinked directly into `~/.config/hypr/`. `omarchy-refresh-config` (the machinery behind the "Refresh Hyprland" menu entry) does `cp -f "$default" "$user_config_file"` — since the destination is a symlink, this writes straight through it into the repo file, silently replacing our customizations with Omarchy's stock template. It does leave a timestamped `~/.config/hypr/<file>.lua.bak.<epoch>` backup, and the repo's git history is a second line of defense, but **never run `omarchy-refresh-hyprland`** (or `omarchy-refresh-config` on any `hypr/*.lua` path) on this machine. If it happens anyway: `git -C env checkout -- config/hypr/*.lua && hyprctl reload`.

## `env/` layout

- `config/<app>/` — user app configs symlinked into `~/.config` or `~/` (fish, git, nvim, hypr, ghostty, gtk, omarchy, claude, claude-personal).
- `modules/<name>/` — installer modules (`module.sh` + `module.conf`).
- `system/{etc,usr-lib,usr-local-bin,user}/` — managed system files, grouped so the subpath mirrors the final destination.
- `systemd/` — user systemd units. `lib/common.sh` — shared helpers. `docs/` — `layout.md`, `modules.md`, `recovery.md`.

## Claude Code config (two-account routing)

This repo manages Claude Code's own config. **Two accounts** are routed by working directory via `env/config/fish/functions/claude.fish`:

- `~/Projects` and below → default `~/.claude` (nucicer.com work account).
- everywhere else → `CLAUDE_CONFIG_DIR=~/.claude-personal` (personal account).

`CLAUDE.md` and custom agents are **shared** (one source in `config/claude/`, symlinked into both account dirs); only `settings.json` differs per account (`config/claude/settings.json` vs `config/claude-personal/settings.json`). The `claude` module links these; secrets and session state in `~/.claude` are intentionally left unmanaged. See `env/modules/claude/module.sh`.

## Secrets

Managed with Proton Pass CLI, not stored in the repo:

```fish
pass-cli login
load_secrets   # also writes ~/.config/pi/local-model.env (mode 600)
```
