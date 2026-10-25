# Konsole tab colour for Claude Code: `ktab_claude` replaces `command claude`
# inside the user's claude() function. Source from ~/.zshrc.

typeset -g _KTAB_BIN="${KTAB_BIN:-${${(%):-%x}:A:h:h}/plugin/bin/ktab}"

# Strips -C/--color, passes everything else through; flags after `--` are untouched.
ktab_claude() {
  emulate -L zsh
  local ktab=$_KTAB_BIN color= name_set= hex= in_konsole= snap= rc arg
  local -a args envs
  local -i i=1

  while (( i <= $# )); do
    arg=${@[i]}
    case $arg in
      --) args+=("${@[i,-1]}"); break ;;
      -C|--color) color=${@[i+1]}; (( i += 2 )); continue ;;
      -C=*|--color=*) color=${arg#*=}; (( i++ )); continue ;;
      -n|-n?*|--name|--name=*) name_set=1 ;;
    esac
    args+=("$arg")
    (( i++ ))
  done

  [[ -n $KONSOLE_DBUS_SESSION ]] && "$ktab" in-konsole && in_konsole=1
  if [[ -n $color ]]; then
    if [[ -z $in_konsole ]]; then
      print -u2 "claude: -C $color ignored: not running in Konsole"
    elif ! hex=$("$ktab" resolve "$color"); then
      print -u2 "claude: unknown colour '$color', -C ignored"
    fi
  fi

  [[ -n $hex ]] && envs+=(KTAB_COLOR=$hex)
  [[ -n $name_set ]] && envs+=(KTAB_NAME_SET=1)

  # Snapshot even without -C: auto-mode and resume may recolour the tab.
  if [[ -n $in_konsole ]]; then
    snap=$("$ktab" get 2>/dev/null)
    [[ -n $hex ]] && "$ktab" set "$hex"
  fi

  {
    command env "${envs[@]}" claude "${args[@]}"
    rc=$?
  } always {
    [[ -n $in_konsole ]] && "$ktab" restore "$snap"
  }
  return $rc
}
