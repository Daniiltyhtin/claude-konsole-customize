#!/usr/bin/env bash
# Builds Konsole from the Arch PKGBUILD with the full-tab-colour patch (KTD13).
# Usage: rebuild.sh          build; prints the install command for the user
#        rebuild.sh --check  is the installed Konsole patched and current?

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PATCH_NAME=0001-full-tab-color.patch
PATCH="$HERE/patches/$PATCH_NAME"
SUFFIX=90
WORK="${KTAB_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-konsole-customize/build}"
PACKAGING=https://gitlab.archlinux.org/archlinux/packaging/packages/konsole.git

version_of() { # version_of <repo/pkg or pkg>: first Version line of pacman -Si
  LC_ALL=C pacman -Si "$1" | awk -F': *' '/^Version/ {print $2; exit}'
}
pkgver_of() { local v="${1%-*}"; echo "${v#*:}"; }

check() {
  local installed target
  installed=$(LC_ALL=C pacman -Q konsole | awk '{print $2}')
  target=$(version_of konsole)
  if [[ "$installed" != *".$SUFFIX" ]]; then
    echo "unpatched Konsole installed ($installed): run $0"
    return 1
  fi
  if [[ $(vercmp "$(pkgver_of "$installed")" "$(pkgver_of "$target")") -lt 0 ]]; then
    echo "new Konsole available ($target, patched $installed is older): run $0"
    return 1
  fi
  echo "patched and current ($installed)"
}

if [[ "${1:-}" == --check ]]; then
  check
  exit $?
fi

ver=$(version_of extra/konsole)
tag="${ver//:/-}"
dir="$WORK/konsole-$tag"
echo "== Konsole $ver -> $dir"

rm -rf "$dir"
# Downloaded tarballs survive re-runs, so a flaky mirror costs one retry, not a full fetch.
export SRCDEST="$WORK/sources"
mkdir -p "$WORK" "$SRCDEST"
git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" "$PACKAGING" "$dir"
cp "$PATCH" "$dir/"
cd "$dir"

# Patch hook-in: add the patch source and a prepare() that applies it.
rel=$(sed -n 's/^pkgrel=//p' PKGBUILD)
sed -i "s/^pkgrel=.*/pkgrel=${rel}.${SUFFIX}/" PKGBUILD
if grep -q '^prepare()' PKGBUILD; then
  sed -i 's/^prepare()/_ktab_orig_prepare()/' PKGBUILD
  orig_call='_ktab_orig_prepare'
else
  orig_call=':'
fi
cat >>PKGBUILD <<EOF

source+=($PATCH_NAME)
prepare() {
  $orig_call
  patch -d "\$pkgname-\$pkgver" -p1 -i "\$srcdir/$PATCH_NAME"
}
EOF
updpkgsums >"$WORK/sums.log" 2>&1 || { echo "updpkgsums failed, see $WORK/sums.log" >&2; exit 2; }

# The packaging repo ships the release signing keys.
if compgen -G 'keys/pgp/*.asc' >/dev/null; then
  gpg --quiet --import keys/pgp/*.asc 2>/dev/null || true
fi
missing_keys=()
for k in $(bash -c 'source ./PKGBUILD; printf "%s\n" "${validpgpkeys[@]}"'); do
  gpg --list-keys "$k" >/dev/null 2>&1 || missing_keys+=("$k")
done
if ((${#missing_keys[@]})); then
  echo "missing PGP keys: ${missing_keys[*]}" >&2
  echo "run: gpg --recv-keys ${missing_keys[*]}" >&2
  exit 3
fi

mapfile -t missing < <(bash -c 'source ./PKGBUILD; printf "%s\n" "${depends[@]}" "${makedepends[@]}"' | xargs pacman -T || true)
if ((${#missing[@]})); then
  echo "missing build dependencies; install them, then re-run $0:" >&2
  echo "  sudo pacman -S --needed --asdeps ${missing[*]}" >&2
  exit 4
fi

if ! makepkg --nobuild -f >"$WORK/prepare.log" 2>&1; then
  echo "download/extract/patch failed (does the patch still apply to $ver?), see $WORK/prepare.log" >&2
  exit 5
fi
makepkg -e -f >"$WORK/build.log" 2>&1 || { echo "build failed, see $WORK/build.log" >&2; exit 6; }

pkg=$(ls -1 "$dir"/konsole-[0-9]*.pkg.tar.* | grep -v -- '-debug-' | head -1)
echo "built: $pkg"
echo "install it with:"
echo "  sudo pacman -U $pkg"
