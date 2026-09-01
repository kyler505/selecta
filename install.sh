#!/bin/sh
set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${TMENU_BIN_DIR:-$HOME/.local/bin}"
CONFIG="${GHOSTTY_CONFIG:-$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty}"
MENU_BIN="$BIN_DIR/tmenu"

mkdir -p "$BIN_DIR"
ln -sf "$REPO_DIR/tmenu" "$MENU_BIN"

if [ ! -f "$CONFIG" ]; then
  echo "error: ghostty config not found: $CONFIG" >&2
  exit 1
fi

cp "$CONFIG" "$CONFIG.bak-tmenu"

if grep -q "^command = .*ghostty-herdr-session" "$CONFIG"; then
  sed -i '' "s|^command = .*ghostty-herdr-session|command = $MENU_BIN|" "$CONFIG"
elif grep -q "^command = $MENU_BIN" "$CONFIG"; then
  : # already installed; keep idempotent
else
  echo "error: no 'command =' line to replace in $CONFIG" >&2
  exit 1
fi

echo "installed: $MENU_BIN -> command = $MENU_BIN"
