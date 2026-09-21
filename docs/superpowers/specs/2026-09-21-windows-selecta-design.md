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

A new WezTerm window opens PowerShell 7 and shows the same selecta menu the zsh
script shows, with Windows destinations: Windows herdr, WSL, a plain
PowerShell 7, and one entry per host in the Windows `~/.ssh/config`.

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
- Same fzf menu as the zsh script (`--height=100% --border --no-multi`, a
  header, `Open: ` prompt), installed with `scoop install fzf`. A second,
  hand-rolled picker on one platform would be a second UX to keep in sync.
- Same entry order as the zsh script, with the platform substitutions: `tmux`
  becomes `wsl`, and `shell` is PowerShell 7 rather than zsh. SSH hosts come
  from the Windows `~/.ssh/config`, parsed by the same rules.
- The `herdr` entry starts the local Windows herdr server. WSL panes come from
  herdr's saved `WSL` machine, not from this menu.

## Architecture

`selecta.ps1`, one file, small testable functions:

- `Get-SelectaHosts` - parse `~/.ssh/config` `Host` lines, strip comments, drop
  pattern hosts (`*`, `?`, `!`), split multi-name lines, sort unique.
  `$env:SELECTA_SSH_CONFIG_FILE` overrides the path, as in the zsh tests.
- `Get-SelectaEntries` - fixed order, an entry is omitted when its binary is
  missing: `herdr`, `wsl`, `shell` (always), then `ssh: <host>` per host.
- `Get-SelectaTarget -Entry <name>` - single source of truth for dispatch. It
  returns the executable, its argument array, and whether a shell follows.
  Unknown entries resolve to the plain-shell target.
- `Get-SelectaCommand -Entry <name>` - renders the target as one command string
  for `-Print` and for tests, quoting arguments that contain spaces.
- `main` - `-Print` dry-run, `SELECTA_SKIP` bypass, fzf-missing fallback, then
  the fzf menu. It runs only when the file is executed, not dot-sourced, so
  tests can load the functions.

Targets:

| Entry         | Command                                                          |
| ------------- | ---------------------------------------------------------------- |
| `herdr`       | `herdr`, then `pwsh -NoLogo` after detach                        |
| `wsl`         | `wsl.exe -d Ubuntu -- /bin/sh -c 'cd ~ && exec /usr/bin/zsh -l'` |
| `shell`       | `pwsh -NoLogo`                                                   |
| `ssh: <host>` | `ssh -t <host> 'export PATH=...; fastfetch; exec "${SHELL:-/bin/sh}" -l'` (identical remote command to the zsh version) |

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

- fzf missing - print a one-line notice, open PowerShell. Never block terminal
  use.
- `wsl.exe` or `herdr` missing - the entry is absent from the menu.
- No `~/.ssh/config` or no hosts - no SSH entries.
- Esc, Ctrl-C, empty or unknown selection - plain PowerShell.

## Testing

- `tests/run.ps1` mirrors `tests/run.sh` and reuses `tests/fixtures/ssh_config`:
  host parsing (patterns skipped, multi-name lines split, sorting,
  case-insensitive directives), entry assembly with fake binaries on a stripped
  `PATH`, a missing ssh config, dispatch for every entry plus a garbage entry,
  and `SELECTA_WSL_DISTRO`.
- Manual smoke test in a real WezTerm window: the fzf menu renders, `shell`
  gives a PowerShell prompt, `wsl` lands in `/home/kcao` under zsh, `herdr`
  starts the Windows server.

## Non-goals

- No change to the zsh `selecta` or its ghostty installer.
- No herdr machine listing and no tmux entry on Windows.
- No automated rewrite of `wezterm.lua`.
