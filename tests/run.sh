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

exit $fail
