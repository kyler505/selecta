#!/bin/sh
set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${SELECTA_BIN_DIR:-$HOME/.local/bin}"
CONFIG="${SELECTA_GHOSTTY_CONFIG:-$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty}"
MENU_BIN="$BIN_DIR/selecta"

mkdir -p "$BIN_DIR"
ln -sf "$REPO_DIR/selecta" "$MENU_BIN"

if [ ! -f "$CONFIG" ]; then
  echo "error: ghostty config not found: $CONFIG" >&2
  exit 1
fi

if [ ! -e "$CONFIG.bak-selecta" ] && [ ! -L "$CONFIG.bak-selecta" ]; then
  cp "$CONFIG" "$CONFIG.bak-selecta"
fi

# Rewrite through a temp file rather than `sed -i`: the in-place flag needs a
# mandatory empty arg on BSD sed and rejects one on GNU sed, so no single
# invocation works on both macOS and Linux/WSL.
rewrite() { # pattern
  sed "s|$1|command = $MENU_BIN|" "$CONFIG" > "$CONFIG.selecta-tmp"
  mv "$CONFIG.selecta-tmp" "$CONFIG"
}

if grep -q "^command = .*ghostty-herdr-session" "$CONFIG"; then
  rewrite "^command = .*ghostty-herdr-session"
elif grep -q "^command = .*tmenu$" "$CONFIG"; then
  rewrite "^command = .*tmenu$"
elif grep -q "^command = $MENU_BIN" "$CONFIG"; then
  : # already installed; keep idempotent
else
  echo "error: no 'command =' line to replace in $CONFIG" >&2
  exit 1
fi

echo "installed: $MENU_BIN -> command = $MENU_BIN"
