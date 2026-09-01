# term-menu

Destination picker for new terminal windows. Every ghostty window opens a menu:
Herdr, Tmux, a plain shell, or SSH into any host in `~/.ssh/config`.

## Install

```sh
./install.sh
```

- Symlinks `tmenu` to `~/.local/bin/tmenu`.
- Replaces the `command =` line in the ghostty config
  (`~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`) with
  `command = ~/.local/bin/tmenu`, keeping a backup at `config.ghostty.bak-tmenu`.
- Idempotent; the `env = PATH=...` line is left untouched.

Restart ghostty (or open a new window). To restore the old behavior, point
`command =` back at `ghostty-herdr-session` (see the backup file) and remove
the `~/.local/bin/tmenu` symlink.

## Menu

| Entry        | Action                                             |
| ------------ | -------------------------------------------------- |
| `herdr`      | Launch/attach Herdr; returns to a zsh prompt after detach |
| `tmux`       | `tmux new -A` (attach most-recent session, else create); quitting closes the window |
| `shell`      | Fresh interactive login zsh                        |
| `ssh: <host>`| `ssh <host>`; quitting closes the window          |

Esc or Ctrl-C lands on a plain shell. Set `TMENU_SKIP=1` (e.g. a second ghostty
profile, or `ghostty -e env TMENU_SKIP=1 tmenu`) to skip the menu entirely.

## Requirements

zsh, fzf, tmux, herdr (the menu omits entries for missing binaries). Hosts come
from `~/.ssh/config`; pattern hosts (`*`, `?`, `!`) are skipped.
