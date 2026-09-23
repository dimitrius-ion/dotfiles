# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository shape

This is a **two-repo dotfiles system** for Arch Linux + Omarchy:

- **`~/Personal/dotfiles`** (this repo, public) — just a bootstrap. Contains `setup.sh` (installs git, sets up GitHub SSH, clones this repo + the private submodule, runs the installer) and the `env/` submodule pointer. Almost nothing else lives here.
- **`env/`** (private submodule, `git@github.com:dimitrius-ion/env.git`) — the actual dotfiles: all configs, installer modules, and system files. **This is where nearly all work happens.**

Because `env/` is a submodule, changes there are committed in `env/` first, then the pointer is bumped in `~/Personal/dotfiles` (the recent commit log here is almost entirely `chore(env): Bump submodule ...`).

`env/` itself nests further submodules (see `env/.gitmodules`): `external/pi` and a ZMK keyboard firmware repo.

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

1. **Discovery** — scans `env/modules/*/`, each providing `module.sh` (logic) and `module.conf` (metadata: `name`, `priority`, `enabled_by_default`, `depends`, `remember`).
2. **Ordering** — modules run in `priority` order (ascending), but `depends=` forces a topological sort via `visit_module`. Cyclic or unknown dependencies abort the install.
3. **Execution** — each `module.sh` is **sourced** (not executed) into the installer's shell, so it inherits helpers and shared arrays. Default-disabled modules (`enabled_by_default=false`: `pi`, `graphiti`, `debloat`) run only with `-a` or an explicit `-m`.
4. **Memory** — a default-disabled module that has actually run is recorded in `~/.local/state/dotfiles/installed-modules`, so later full installs restore it instead of leaving its symlinks orphaned. `remember=false` in `module.conf` opts out of that (only `debloat` does, since it is a one-shot package removal that must never re-run implicitly). Edit that state file to make the installer forget a module.

Current priority order: `fish`(10) → `claude`/`dependencies`(20) → `proton`(30) → `omarchy-plugins`(35) → `symlinks`(40) → `system`(50) → ... → `pi`(130)/`sublime-merge`(130) → `graphiti`(140) → `debloat`(200). Run `./install.sh -l` for the live list rather than trusting this one.

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
- For files Omarchy regenerates, keep our changes in a separate override file and **idempotently append an include** to Omarchy's file — `config-file = ...overrides` (ghostty) or `@import "geary-overrides.css"` (GTK) — or, where the format has no include mechanism, a `jq` merge (the quickshell bar's `omarchy/shell.json`; see the plugins section below for its precedence rules).
- See `env/modules/symlinks/module.sh` for all of these; it's the reference for the extend-don't-replace approach.

Omarchy's own defaults also load *before* our config, and what they cover shifts between releases — 4.0 moved app/web-app keybindings into `default/hypr/bindings/applications.lua`, so re-declaring one leaves two binds firing on the same combo. After an Omarchy upgrade, check with:

```bash
hyprctl binds -j | jq 'map(select(.key != "")) | group_by([.modmask,.key]) | map(select(length > 1))'
```

**Danger: `omarchy-refresh-hyprland` / `omarchy-refresh-config hypr/*.lua` destroys these files.** Unlike `hyprland.conf`/`hyprland.lua` (deliberately left to Omarchy, restored via `restore_omarchy_config`), `config/hypr/{autostart,bindings,input,looknfeel,monitors}.lua` are symlinked directly into `~/.config/hypr/`. `omarchy-refresh-config` (the machinery behind the "Refresh Hyprland" menu entry) does `cp -f "$default" "$user_config_file"` — since the destination is a symlink, this writes straight through it into the repo file, silently replacing our customizations with Omarchy's stock template. It does leave a timestamped `~/.config/hypr/<file>.lua.bak.<epoch>` backup, and the repo's git history is a second line of defense, but **never run `omarchy-refresh-hyprland`** (or `omarchy-refresh-config` on any `hypr/*.lua` path) on this machine. If it happens anyway: `git -C env checkout -- config/hypr/*.lua && hyprctl reload`.

## Omarchy shell plugins (quickshell bar)

`env/modules/omarchy-plugins/` (priority 35, just ahead of `symlinks`) owns everything under `~/.config/omarchy/plugins/`. Two kinds:

- **Ours** — hand-written QML in `env/config/omarchy/plugins/<id>/`, symlinked into place (currently `dimitrius.iwd-network`).
- **Third-party** — declared as `<id>|<git url>` pairs in the `OMARCHY_GIT_PLUGINS` array and installed with `omarchy plugin add`, which owns the checkout and can `omarchy plugin update` it later (currently `lgse.sandman`, `io.github.sirjul1337.lock-explorer`, `omaplug`, `io.github.tallsam.navbar-cat`, `bobbynicholas.omaland`, `jankeesvw.notification-center`, `omamail`, `io.github.chris.desktop-undo`). Keep this list in step with `OMARCHY_GIT_PLUGINS`; installing by hand and not declaring it means the next `symlinks` run drops the widget from the bar and its settings from `shell.json`. **Don't vendor these as submodules** — that fights the plugin CLI's own registry for no gain while we aren't patching them. Fork and swap the URL if that changes.

`omaplug` is a plugin manager widget that can enable, disable, install and remove plugins from the bar — but `plugins` and `disabledPlugins` are declared in `shell-override.json`, so **the next `symlinks` run reverts any toggle made there**. Use it to browse, try and update, then mirror anything worth keeping into `OMARCHY_GIT_PLUGINS` and the override.

Middle-click (`mouse:274`) closes the window under the cursor, bound **without a modifier**, so it grabs middle click globally — middle-click paste in terminals and middle-click-open-link in browsers do not reach the application. That cost is accepted deliberately; it also means tmux never sees a middle click, so there is no point binding one in `overrides.conf`.

Window-close undo used to be a hand-rolled stash (`window-stash.sh`, soft-close into a `special:stash` workspace). It was retired for `io.github.chris.desktop-undo`, which also covers drags, float toggles, fullscreen and workspace sends. `SUPER+W` and `SUPER+SHIFT+W` are back under Omarchy's defaults. The tradeoff was accepted deliberately: the stash never killed the process so state survived, whereas plugin close-undo relaunches the command.

### tmux config

Omarchy owns `~/.config/tmux/tmux.conf` and `omarchy-refresh-tmux` overwrites it via the same `omarchy-refresh-config` `cp -f` that would write through a symlink into this repo. So tmux.conf stays Omarchy's, our bindings live in `env/config/tmux/overrides.conf`, and the `symlinks` module idempotently appends `source-file ~/.config/tmux/overrides.conf` to the end of Omarchy's file — the ghostty/GTK extend pattern again.

The overrides add vim-style keys *alongside* Omarchy's arrows, never replacing them: `Ctrl+Alt+hjkl` focus, `Ctrl+Alt+Shift+hjkl` resize, `Alt+h`/`Alt+l` window nav, `prefix s`/`S` for `:sp`/`:vs` splits, `prefix n`/`p` for windows.

Two collisions handled, worth not re-introducing:

- **Resize is not on `prefix H/J/K/L`** — Omarchy binds `prefix K` to kill-session, and taking it silently would be a nasty surprise. Resize mirrors the arrow bindings' modifiers instead.
- **`prefix s` normally opens tmux's session picker**, which matters more than usual here since sessions map one-to-one onto terminal windows. It moved to `prefix C-s` rather than being lost.

The prefix is `Ctrl+Space` (Omarchy's choice), with `Ctrl+B` as secondary. `prefix ?` opens Omarchy's keybinding popup.

### Terminals survive Super+Z

`SUPER+RETURN` runs `config/hypr/scripts/terminal-tmux.sh`, not Omarchy's terminal bind. Each window gets its own tmux session whose name is baked into the terminal's argv (`ghostty … -e tmux new -A -s w<hex>`). Closing the window leaves that session on the tmux server with its scrollback and running processes intact, and desktop-undo replays the window's `/proc/<pid>/cmdline` verbatim (`Service.qml:357` → `js/Ops.js:250`), so Super+Z re-runs the identical command and `-A` reattaches that exact session instead of opening a fresh shell.

This is the answer to the one thing relaunch-based undo cannot do. Without it, Super+Z on a terminal returns the cwd and fish's global history but loses the scrollback and anything that was running.

Three things it depends on, none obvious:

- **The session name must be unique per window and present in argv at launch.** Omarchy's own `SUPER+ALT+RETURN` tmux bind attaches a single shared `Work` session — deliberately left alone, it is a different tool.
- **`-A` on `tmux new`**, which attaches rather than failing when the session exists. That one flag is what turns a replayed argv into a reattach.
- **`ghostty -e` spawns its own process** even though Omarchy launches ghostty from a `.desktop` file with `--gtk-single-instance=true`. Windows opened *without* a command all share one process (and therefore one argv, and one `/proc` entry with every window's shells as children), so there is nothing per-window to replay. Don't "simplify" the launcher by dropping the command.

Sessions outlive their windows by design. `terminal-tmux-reap.sh` (daily, via `systemd/tmux-reap.timer`) clears detached sessions idle over 24h, matching only the `w<8 hex>` names this repo generates so hand-made sessions are never touched. They do not survive a reboot regardless — the tmux server is an ordinary user process.

Several plugins write managed blocks into `config/hypr/*.lua`, and those paths are symlinks into the repo — so the block lands in `env/config/hypr/` and shows up in `git diff` as an uncommitted change nobody made by hand:

- **Sandman** — a lid-action block in `bindings.lua`. Unavoidable; it is how the managed lid action works.
- **Omaland** — a `-- >>> omaland managed block >>>` in `looknfeel.lua`, written automatically whenever its panel opens, with no opt-in.
- **Desktop Undo** — offers one in `bindings.lua` via its "Set hotkey" button. Avoidable, and avoided: its three binds are declared in `bindings.lua` directly, so **don't use that button**.

When `git status` in `env/` shows an unexplained `hypr/*.lua` change, check for a fenced managed block before assuming it was you.

A plugin needing a root-owned helper installs it from the module via `sudo_install_exec`, never from the plugin directory itself (Sandman's `sandman-configure-hibernate` → `/usr/local/libexec/`).

### `shell.json` merge precedence

`modules/symlinks/module.sh` rebuilds `~/.config/omarchy/shell.json` as **stock × carried × override**, last wins:

1. **stock** — `~/.local/share/omarchy/config/omarchy/shell.json`.
2. **carried** — only the keys in the module's `carry_keys` (`idle`, `cloneSourceRestores`) survive from the live file. `idle` is Sandman's screensaver/lock timeouts; re-asserting stock would silently undo the bar UI on every install. `cloneSourceRestores` is the plugin CLI's bookkeeping for restoring a built-in when a cloned plugin is removed.
3. **override** — `env/config/omarchy/shell-override.json`, which declares the bar layout, `plugins` and `disabledPlugins`.

Everything else in the live file is **destroyed** on every run. That is deliberate for bar layout (it reverts drag-to-reorder gestures back to what the repo declares), but it means anything new the plugin CLI starts writing to `shell.json` must be added to the override or to `carry_keys` — otherwise it silently disappears on the next install. jq's `*` replaces arrays wholesale, so `bar.layout` sections and `plugins` are listed in full rather than as deltas, and `shell.qml` discards the file unless `version` is 1.

## Power and idle management

Split deliberately between the Sandman plugin and `env/system/`:

- **Sandman owns** lid-close action, screensaver, displays-off (DPMS), auto-lock, sleep, and hibernate-after-sleep. It takes a low-level lid-switch inhibitor instead of editing logind, writes the hibernate delay to `/etc/systemd/sleep.conf.d/90-sandman.conf`, and inserts a managed `-- BEGIN Sandman lid action override` block into `~/.config/hypr/bindings.lua` — **which is a symlink into the repo**, so that block lands in `env/config/hypr/bindings.lua` and shows up in `git diff`.

- **The repo still owns** `99-power-profile.rules` (AC/battery power profile + wifi powersave), `99-low-battery.rules` (hibernate at 5%), `usb-wakeup.sh`, and `battery-notify.sh`. Sandman touches none of these.

Don't reintroduce a `sleep.conf.d/hyprland.conf` or `logind.conf.d/hyprland.conf` drop-in: systemd applies drop-ins in lexicographic order and the last wins, so `hyprland.conf` sorts after `90-sandman.conf` and would silently override whatever the Sandman UI reports. `modules/system/module.sh` sweeps both paths on every run.

Also note Sandman persists an **Off** timeout as a 7-day value in `shell.json`. Removing the plugin while auto-lock is Off leaves a machine that effectively never locks, with no UI left to notice.

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
