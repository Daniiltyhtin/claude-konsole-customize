#!/usr/bin/env bash
# SessionStart: persist launch-time choices; on resume restore colour and pending title.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mark_manual_name

case "$(field source)" in
  startup | clear)
    apply_manual_colour
    ;;
  resume)
    if ! apply_manual_colour; then
      color=$(st color)
      [[ -n "$color" ]] && { "$KTAB" set "$color" || true; }
    fi
    emit_pending_title SessionStart
    ;;
esac
exit 0
