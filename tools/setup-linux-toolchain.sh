#!/usr/bin/env bash
# Install the Swift toolchain on Linux and shim the libraries Arch ships under
# different sonames than the toolchain expects.
#
# Arch tracks upstream faster than the Swift toolchain's build host:
#   libncurses.so.6 -> Arch only ships the wide build, libncursesw.so.6
#   libxml2.so.2    -> Arch is on .so.16 (2.15); ABI differs, so we fetch the old one
#   libicuuc.so.76  -> Arch is on ICU 78
#
# Old .so files come from the Arch Linux Archive rather than being symlinked from
# the new ones — a differing soname means a differing ABI, and pretending
# otherwise segfaults at runtime instead of failing to load.
set -euo pipefail

COMPAT="$HOME/.local/share/swiftly/compat"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! command -v swiftly >/dev/null && [ ! -x "$HOME/.local/share/swiftly/bin/swiftly" ]; then
  echo "==> installing swiftly"
  curl -sL -o "$WORK/swiftly.tar.gz" "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
  tar xzf "$WORK/swiftly.tar.gz" -C "$WORK"
  "$WORK/swiftly" init --quiet-shell-followup --assume-yes
fi

export PATH="$HOME/.local/share/swiftly/bin:$PATH"
swiftly install --use latest 2>/dev/null || true

echo "==> shimming libraries into $COMPAT"
mkdir -p "$COMPAT"
ln -sf /usr/lib/libncursesw.so.6 "$COMPAT/libncurses.so.6"

fetch_arch_pkg() {  # $1 = pkg name, $2 = versioned filename, $3 = glob of libs to keep
  local dir="$WORK/$1"
  mkdir -p "$dir"
  curl -sL -o "$dir/pkg.tar.zst" "https://archive.archlinux.org/packages/${1:0:1}/$1/$2"
  bsdtar xf "$dir/pkg.tar.zst" -C "$dir" usr/lib/
  cp -P "$dir"/usr/lib/$3 "$COMPAT/"
}

[ -e "$COMPAT/libxml2.so.2" ]   || fetch_arch_pkg libxml2 libxml2-2.13.8-1-x86_64.pkg.tar.zst 'libxml2.so.2*'
[ -e "$COMPAT/libicuuc.so.76" ] || fetch_arch_pkg icu     icu-76.1-1-x86_64.pkg.tar.zst       'libicu*.so.76*'

echo
echo "Done. Source env.sh before building:"
echo "    . ./env.sh && swift test"
