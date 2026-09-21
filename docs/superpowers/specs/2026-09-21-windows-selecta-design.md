# windows-selecta design

Date: 2026-09-21
Status: Approved by user

## Problem

On Windows, WezTerm boots every new window into WSL (`default_domain =
'WSL:Ubuntu'`), and the WSL domain's `default_prog` runs the zsh `selecta`
inside the distro. That made sense while the multiplexer lived in WSL. It no
longer does: herdr now ships a Windows build (0.9.1) and reaches the distro
through its own remote-server support - the Windows herdr already holds a saved
machine `WSL` pointing at the `wsl` ssh host (`127.0.0.1:2222`, WSL sshd
active). Booting into WSL first only adds a hop, and it puts the picker on the
wrong side of the boundary.

## Goal

A new WezTerm window opens PowerShell 7 and shows a Windows-side picker with
three destinations: PowerShell 7, WSL, and Windows herdr.

## Decisions

- New script `selecta.ps1` in this repo. The zsh `selecta`, `install.sh`, and
  `tests/run.sh` stay unchanged: macOS/ghostty and in-distro use continue.
- The Windows entry point is a second clone of this repo at
  `C:\Users\kcao\.local\share\selecta`. PowerShell cannot run the WSL copy
  through `\\wsl.localhost` without starting the distro first, which defeats the
  purpose.
- No `install.ps1`. WezTerm's `default_prog` points straight at the script:
  `{ 'pwsh', '-NoLogo', '-NoProfile', '-File',
  'C:\Users\kcao\.local\share\selecta\selecta.ps1' }`. This is a one-time
  config edit, so an installer that rewrites Lua is not justified.
- Built-in key picker, no fzf: fzf is not installed on Windows, and a
  three-entry list does not need fuzzy search. Up/Down or `1`-`3` moves, Enter
  opens, Esc opens a plain PowerShell.
- No SSH host list on the Windows side. herdr owns remote machines now, and the
  only host in the Windows `~/.ssh/config` is `wsl`, which already has its own
  entry.
- The `herdr` entry starts the local Windows herdr server. WSL panes come from
  herdr's saved `WSL` machine, not from this menu.

## Architecture

`selecta.ps1`, one file, small testable functions:

- `Get-SelectaEntries` - fixed order, an entry is omitted when its binary is
  missing: `pwsh` (always, it is the host process), `wsl` (needs `wsl.exe`),
  `herdr` (needs `herdr`).
- `Get-SelectaTarget -Entry <name>` - single source of truth for dispatch. It
  returns the executable, its argument array, and whether a shell follows.
  Unknown entries resolve to the plain-shell target.
- `Get-SelectaCommand -Entry <name>` - renders the target as one command string
  for `-Print` and for tests.
- `Show-SelectaMenu` - draws the list, reads keys, returns the selection. The
  highlight uses the `#89dceb` accent shared with `wezterm.lua` and the herdr
  config.
- `main` - runs only when the file is executed, not dot-sourced, so tests can
  load the functions.

Targets:

| Entry   | Command                                                            |
| ------- | ------------------------------------------------------------------ |
| `pwsh`  | `pwsh -NoLogo`                                                     |
| `wsl`   | `wsl.exe -d Ubuntu -- /bin/sh -c 'cd ~ && exec /usr/bin/zsh -l'`   |
| `herdr` | `herdr`, then `pwsh -NoLogo` after detach                          |

The home directory comes from a shell-side `cd ~`, not `wsl --cd ~`: PowerShell
resolves a bare `~` argument to the Windows home before `wsl.exe` sees it, so
`--cd ~` lands in `/mnt/c/Users/kcao` (measured, 2026-09-21).

PowerShell has no `exec`. Each target runs as a child process in the same
console, and `selecta.ps1` exits with the child's code right after, so closing
the destination closes the pane - the same behavior the zsh version gets from
`exec`. The `herdr` entry keeps the zsh version's rule and drops to a shell
after detach.

`$env:SELECTA_WSL_DISTRO` overrides the distro name (default `Ubuntu`).
`$env:SELECTA_SKIP=1` opens PowerShell without the menu.

## WezTerm changes (`~/.config/wezterm/wezterm.lua`)

- Delete `config.default_domain = 'WSL:Ubuntu'`; new windows use the Windows
  local domain again.
- `config.default_prog` runs `selecta.ps1` as above.
- The `WSL:Ubuntu` domain stays for the launcher, but its `default_prog` becomes
  a plain `cd ~ && exec /usr/bin/zsh -l`. A picker inside the picker is wrong
  now that the Windows side owns the choice.
- Drop the `Ubuntu (plain shell)` launcher entry: with the domain no longer
  starting a menu, it duplicates `Ubuntu (WSL)`.

## Error handling

- Input redirected or no console - print a notice, open PowerShell.
- `wsl.exe` or `herdr` missing - the entry is absent from the menu.
- Esc, Ctrl-C, or an unknown selection - plain PowerShell.

## Testing

- `tests/run.ps1`: `Get-SelectaEntries` with a stripped `PATH` (only `pwsh`
  survives) and with the real one; `Get-SelectaCommand` for each entry plus a
  garbage entry; `SELECTA_WSL_DISTRO` honored.
- Manual smoke test in a real WezTerm window: the menu renders, `pwsh` gives a
  prompt, `wsl` lands in `/home/kcao` under zsh, `herdr` starts the Windows
  server.

## Non-goals

- No change to the zsh `selecta` or its ghostty installer.
- No SSH entries, no herdr machine listing, no tmux entry on Windows.
- No automated rewrite of `wezterm.lua`.
