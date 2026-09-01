#!/bin/zsh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../selecta"

fail=0
check() { # name expected actual
  if [[ "$2" != "$3" ]]; then
    print -u2 "FAIL: $1\nexpected: [$2]\nactual:   [$3]"
    fail=1
  else
    print "ok: $1"
  fi
}

export SELECTA_SSH_CONFIG_FILE="$SCRIPT_DIR/fixtures/ssh_config"

hosts="$(selecta_hosts)"
check "hosts parsed, sorted, patterns skipped, case-insensitive directives" \
  $'homelab\nhp\nlower\nmixed\nopmicro\nupper' "$hosts"

# Entry assembly: fake binaries in a temp dir, real PATH stripped of tmux/herdr.
tmpbin="$(mktemp -d)"
trap 'rm -rf "$tmpbin"' EXIT
touch "$tmpbin/tmux" "$tmpbin/herdr"
chmod +x "$tmpbin/tmux" "$tmpbin/herdr"

export PATH="$tmpbin:/opt/homebrew/bin:/usr/bin:/bin"
entries="$(selecta_entries)"
check "entries with tmux+herdr present" \
  $'herdr\ntmux\nshell\nssh: homelab\nssh: hp\nssh: lower\nssh: mixed\nssh: opmicro\nssh: upper' "$entries"

export PATH="/usr/bin:/bin"
entries="$(selecta_entries)"
check "entries without tmux/herdr" \
  $'shell\nssh: homelab\nssh: hp\nssh: lower\nssh: mixed\nssh: opmicro\nssh: upper' "$entries"

# Dispatch dry-run via --print (avoids exec in tests).
check "dispatch tmux"      "exec tmux new -A"          "$(selecta_dispatch tmux print)"
check "dispatch ssh with fastfetch" \
  "exec ssh -t hp 'export PATH=\"\$HOME/.local/bin:\$PATH\"; command -v fastfetch >/dev/null 2>&1 && fastfetch; exec \"\${SHELL:-/bin/sh}\" -l'" \
  "$(selecta_dispatch 'ssh: hp' print)"
check "dispatch herdr"     "herdr; exec /bin/zsh -il"  "$(selecta_dispatch herdr print)"
check "dispatch shell"     "exec /bin/zsh -il"         "$(selecta_dispatch shell print)"
check "dispatch garbage"   "exec /bin/zsh -il"         "$(selecta_dispatch 'bogus' print)"

# install.sh: config rewrite, idempotency, env overrides.
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir" "$tmpbin"' EXIT
cp "$SCRIPT_DIR/fixtures/ghostty_config" "$tmpdir/config.ghostty"
export SELECTA_BIN_DIR="$tmpdir/bin" SELECTA_GHOSTTY_CONFIG="$tmpdir/config.ghostty"
"$SCRIPT_DIR/../install.sh" >/dev/null
check "install rewrites command line" \
  "command = $tmpdir/bin/selecta" \
  "$(grep -m1 '^command = ' "$tmpdir/config.ghostty")"
check "install keeps env line" \
  "env = PATH=/Users/kcao/.bun/bin:/opt/homebrew/bin:/usr/bin:/bin" \
  "$(grep -m1 '^env = ' "$tmpdir/config.ghostty")"
check "install creates backup" \
  "1" "$(test -f "$tmpdir/config.ghostty.bak-selecta" && print 1 || print 0)"
check "install symlinks selecta" \
  "1" "$(test -L "$tmpdir/bin/selecta" && print 1 || print 0)"
"$SCRIPT_DIR/../install.sh" >/dev/null
check "install preserves original backup" \
  "command = /Users/kcao/.local/bin/ghostty-herdr-session" \
  "$(grep -m1 '^command = ' "$tmpdir/config.ghostty.bak-selecta")"
check "install is idempotent" \
  "1" "$(grep -c '^command = ' "$tmpdir/config.ghostty")"

exit $fail
