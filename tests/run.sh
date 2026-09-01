#!/bin/zsh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../tmenu"

fail=0
check() { # name expected actual
  if [[ "$2" != "$3" ]]; then
    print -u2 "FAIL: $1\nexpected: [$2]\nactual:   [$3]"
    fail=1
  else
    print "ok: $1"
  fi
}

export SSH_CONFIG_FILE="$SCRIPT_DIR/fixtures/ssh_config"

hosts="$(tmenu_hosts)"
check "hosts parsed, sorted, patterns skipped" $'homelab\nhp\nopmicro' "$hosts"

# Entry assembly: fake binaries in a temp dir, real PATH stripped of tmux/herdr.
tmpbin="$(mktemp -d)"
trap 'rm -rf "$tmpbin"' EXIT
touch "$tmpbin/tmux" "$tmpbin/herdr"
chmod +x "$tmpbin/tmux" "$tmpbin/herdr"

export PATH="$tmpbin:/opt/homebrew/bin:/usr/bin:/bin"
entries="$(tmenu_entries)"
check "entries with tmux+herdr present" \
  $'herdr\ntmux\nshell\nssh: homelab\nssh: hp\nssh: opmicro' "$entries"

export PATH="/usr/bin:/bin"
entries="$(tmenu_entries)"
check "entries without tmux/herdr" \
  $'shell\nssh: homelab\nssh: hp\nssh: opmicro' "$entries"

exit $fail
