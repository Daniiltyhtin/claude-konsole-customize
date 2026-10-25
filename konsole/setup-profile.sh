#!/usr/bin/env bash
# Creates a Konsole profile whose tab title is the program-set title (%w) and
# makes it the default. Usage: setup-profile.sh [--revert]

set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/konsolerc"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/konsole"
NAME=claude-tabs.profile
PROFILE="$DATA/$NAME"
FIRST_BACKUP="$CONF.bak-claude-tabs"

kread() { kreadconfig6 --file "$CONF" --group "$1" --key "$2"; }
kwrite() { kwriteconfig6 --file "$1" --group "$2" --key "$3" "$4"; }

if [[ "${1:-}" == --revert ]]; then
  [[ -f "$FIRST_BACKUP" ]] || { echo "no backup at $FIRST_BACKUP" >&2; exit 1; }
  cp -p "$FIRST_BACKUP" "$CONF"
  echo "restored $CONF; profile $PROFILE left in place"
  exit 0
fi

current=$(kread 'Desktop Entry' DefaultProfile 2>/dev/null || true)
if [[ "$current" == "$NAME" && -f "$PROFILE" ]]; then
  echo "already set up: $PROFILE is the default profile"
  exit 0
fi

# The first-ever backup is kept for --revert.
if [[ -f "$CONF" && ! -f "$FIRST_BACKUP" ]]; then
  cp -p "$CONF" "$FIRST_BACKUP"
fi

parent="FALLBACK/"
if [[ -n "$current" && "$current" != "$NAME" && -f "$DATA/$current" ]]; then
  parent="$DATA/$current"
fi

mkdir -p "$DATA"
kwrite "$PROFILE" General Name "Claude Tabs"
kwrite "$PROFILE" General Parent "$parent"
kwrite "$PROFILE" General LocalTabTitleFormat "%w"
kwrite "$PROFILE" General RemoteTabTitleFormat "%w"
kwrite "$CONF" 'Desktop Entry' DefaultProfile "$NAME"

echo "default profile: $PROFILE (parent: $parent). New tabs show the program-set title."
