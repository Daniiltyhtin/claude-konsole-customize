#!/usr/bin/env bash
# Installs or updates the konsole-tabs plugin in every Claude Code account.
# Usage: ./install.sh [--auto-mode on|off] [--auto-attempts 1-5]

set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
MARKET=claude-konsole-customize
PLUGIN="konsole-tabs@$MARKET"
# Several accounts: KTAB_CONFIG_DIRS="$HOME/.claude $HOME/.claude-work" ./install.sh
read -ra CONFIG_DIRS <<<"${KTAB_CONFIG_DIRS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
auto_mode=""
auto_attempts=""

while (($#)); do
  case "$1" in
    --auto-mode) auto_mode="${2:-}"; shift 2 ;;
    --auto-attempts) auto_attempts="${2:-}"; shift 2 ;;
    *) echo "usage: $0 [--auto-mode on|off] [--auto-attempts 1-5]" >&2; exit 2 ;;
  esac
done
auto_value=""
case "$auto_mode" in
  "") ;;
  on) auto_value=true ;;
  off) auto_value=false ;;
  *) echo "--auto-mode expects on or off" >&2; exit 2 ;;
esac
if [[ -n "$auto_attempts" && ! "$auto_attempts" =~ ^[1-5]$ ]]; then
  echo "--auto-attempts expects a number from 1 to 5" >&2
  exit 2
fi

for dir in "${CONFIG_DIRS[@]}"; do
  [[ -d "$dir" ]] || { echo "skip: $dir does not exist"; continue; }
  echo "== $dir"
  export CLAUDE_CONFIG_DIR="$dir"
  if command claude plugin marketplace list 2>/dev/null | grep -q "$MARKET"; then
    command claude plugin marketplace update "$MARKET"
  else
    command claude plugin marketplace add "$REPO"
  fi
  if command claude plugin list 2>/dev/null | grep -q "$PLUGIN"; then
    command claude plugin update "$PLUGIN"
  else
    command claude plugin install "$PLUGIN"
  fi
  if [[ -n "$auto_value" || -n "$auto_attempts" ]]; then
    jq -nc --arg m "$auto_value" --arg a "$auto_attempts" \
      '{} + (if $m != "" then {auto_mode: $m} else {} end) + (if $a != "" then {auto_attempts: $a} else {} end)' |
      command claude plugin configure "$PLUGIN" --values-stdin
  fi
done

echo "Done. Restart running Claude sessions to load the plugin."
