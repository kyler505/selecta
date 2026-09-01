# term-menu design

Date: 2026-09-01
Status: Approved by user

## Problem

Opening a new ghostty window currently launches straight into Herdr via
`command = /Users/kcao/.local/bin/ghostty-herdr-session` in the ghostty config
(`~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`). There
is no choice of destination: every new window attaches to Herdr.

## Goal

When a new terminal window opens, show a menu offering: Herdr, Tmux, a plain
shell, or SSH into any machine in `~/.ssh/config`.

## Decisions (from brainstorming)

- Standalone repo in Sandbox: `~/Sandbox/term-menu`, git-initialized.
- One zsh script, `tmenu`. No build step; the only external dependency is fzf
  (already installed at `/opt/homebrew/bin/fzf`).
- Trigger via the ghostty `command =` line, NOT a shell rc hook. The ghostty
  config already owns window startup; replacing the command line preserves the
  existing launch pattern. No `$TMUX`/`$HERDR_ENV`/`$SSH_CONNECTION` guards are
  needed because the menu only ever runs in a fresh ghostty window.
- exec semantics: tmux and SSH selections exec, so quitting them closes the
  window. Herdr runs in the foreground and falls back to a fresh login shell
  after detach - identical to today's `ghostty-herdr-session` behavior. The
  shell selection execs a fresh `zsh -il`.
- SSH entries are generated from `~/.ssh/config`: one entry per non-pattern
  `Host` (skip lines containing `*`, `?`, or `!`), sorted. `~/.ssh/config` is
  the single source of truth; no separate menu config file.
- `TMENU_SKIP=1` env bypass for one-off skip (second ghostty profile, or
  `ghostty -e env TMENU_SKIP=1 tmenu`). Esc / Ctrl-C in the menu also lands on
  a plain shell.

## Architecture

Single zsh script `tmenu` with small pure functions so the logic is testable
without a PTY:

- `tmenu_hosts()` - parse `~/.ssh/config` `Host` lines, drop pattern lines
  (`*`, `?`, `!`), split multi-name lines, sort unique.
- Entry assembly - fixed entries in order, omitting missing binaries:
  1. `herdr` (only if `herdr` is on PATH)
  2. `tmux` (only if `tmux` is on PATH)
  3. `shell`
  4. `ssh: <host>` for each host.
- fzf invocation - full-screen list, header with hints, `--no-multi`.
- Selection dispatch:
  - `herdr` -> run `herdr`, then `exec /bin/zsh -il`
  - `tmux` -> `exec tmux new -A` (attach most-recent session, create if none)
  - `shell` -> `exec /bin/zsh -il`
  - `ssh: <host>` -> `exec ssh <host>`
  - empty / unknown -> `exec /bin/zsh -il`
- `--print` flag - emit the dispatch command instead of executing it. Used by
  tests and manual verification.
- PATH insurance - prepend `$HOME/.local/bin` and `/opt/homebrew/bin` to PATH
  in-script. GUI-launched processes get a minimal PATH; fzf and herdr must be
  findable regardless of the ghostty `env =` line.

## Install (`install.sh`)

1. Symlink `tmenu` to `~/.local/bin/tmenu` (same directory as
   `ghostty-herdr-session`).
2. In the ghostty config, replace the `command = ...ghostty-herdr-session`
   line with `command = /Users/kcao/.local/bin/tmenu`, after writing a backup
   `config.ghostty.bak-tmenu`. Leave the existing `env = PATH=...` line
   untouched - Herdr and fzf need the full PATH.
3. Idempotent: re-running must not duplicate the command line or symlink.

`ghostty-herdr-session` is left in place; `tmenu` reproduces its behavior for
the herdr entry.

## Error handling

- fzf missing -> print a one-line notice, exec zsh directly. Never block
  terminal use.
- tmux or herdr missing -> omit the corresponding entry.
- No `~/.ssh/config` or no hosts -> omit the SSH section.
- Esc / Ctrl-C / empty selection -> plain shell.
- Unknown selection (should not happen with fzf) -> plain shell.

## Testing

- `tests/run.sh` (plain shell, no bats): unit tests for `tmenu_hosts()` against
  a fixture config (patterns skipped, multi-name lines split, sorting), entry
  assembly (missing-binary omission), and dispatch emission via `--print`.
- PTY smoke test (manual, during verification): launch `tmenu` in a PTY and
  confirm the menu renders; select `shell` and land at a prompt; select `tmux`
  and observe a session start. SSH selection verified via `--print` output
  (do not open real remote connections in tests).

## Non-goals

- No session listing from Herdr or the setpoint daemon.
- No tmux session picker beyond attach-or-create (`tmux new -A`).
- No menu config file; `~/.ssh/config` is the host source.
- No integration with the `agent-terminal-runtime` workspace.
- No Windows support.
