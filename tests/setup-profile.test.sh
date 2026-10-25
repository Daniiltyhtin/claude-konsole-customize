# U5: Konsole profile with %w tab titles.

SETUP="$REPO/konsole/setup-profile.sh"

prep() {
  export XDG_CONFIG_HOME="$T/config" XDG_DATA_HOME="$T/data"
  mkdir -p "$XDG_CONFIG_HOME"
  printf '[General]\nConfigVersion=1\n\n[UiSettings]\nColorScheme=\n' >"$XDG_CONFIG_HOME/konsolerc"
}

rc() { kreadconfig6 --file "$XDG_CONFIG_HOME/konsolerc" --group "$1" --key "$2"; }
prof() { kreadconfig6 --file "$XDG_DATA_HOME/konsole/claude-tabs.profile" --group General --key "$1"; }
backups() { ls "$XDG_CONFIG_HOME" | grep -c 'konsolerc.bak-' || true; }

test_creates_profile_and_sets_default_with_backup() {
  prep
  "$SETUP" >/dev/null &&
    assert_eq "$(prof LocalTabTitleFormat)" "%w" &&
    assert_eq "$(prof RemoteTabTitleFormat)" "%w" &&
    assert_eq "$(prof Parent)" "FALLBACK/" &&
    assert_eq "$(rc 'Desktop Entry' DefaultProfile)" "claude-tabs.profile" &&
    assert_eq "$(backups)" "1"
}

test_is_idempotent() {
  prep
  "$SETUP" >/dev/null && "$SETUP" >/dev/null &&
    assert_eq "$(backups)" "1" &&
    assert_eq "$(grep -c LocalTabTitleFormat "$XDG_DATA_HOME/konsole/claude-tabs.profile")" "1"
}

test_keeps_other_sections() {
  prep
  "$SETUP" >/dev/null &&
    assert_eq "$(rc General ConfigVersion)" "1" &&
    assert_contains "$(cat "$XDG_CONFIG_HOME/konsolerc")" "[UiSettings]"
}

test_inherits_existing_custom_default_profile() {
  prep
  mkdir -p "$XDG_DATA_HOME/konsole"
  printf '[General]\nName=Mine\n' >"$XDG_DATA_HOME/konsole/Mine.profile"
  kwriteconfig6 --file "$XDG_CONFIG_HOME/konsolerc" --group 'Desktop Entry' --key DefaultProfile Mine.profile
  "$SETUP" >/dev/null &&
    assert_eq "$(prof Parent)" "$XDG_DATA_HOME/konsole/Mine.profile"
}

test_revert_restores_original_konsolerc() {
  prep
  local before
  before=$(cat "$XDG_CONFIG_HOME/konsolerc")
  "$SETUP" >/dev/null && "$SETUP" --revert >/dev/null &&
    assert_eq "$(cat "$XDG_CONFIG_HOME/konsolerc")" "$before"
}
