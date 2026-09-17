#!/bin/zsh
# Build offtranslate and package the Alfred workflow.
#
#   ./build.sh              build workflow/offtranslate
#   ./build.sh --check      build, then report language availability
#   ./build.sh --package    build, then produce the .alfredworkflow bundle

set -euo pipefail
cd "${0:A:h}"

DEPLOY_TARGET=26.0
BIN=workflow/offtranslate
SRC=src/offtranslate.swift
NAME="Offline Translator"

if ! command -v swiftc >/dev/null 2>&1; then
  print -u2 "swiftc not found. Install the Xcode Command Line Tools: xcode-select --install"
  exit 1
fi

os_major=$(sw_vers -productVersion | cut -d. -f1)
if (( os_major < 26 )); then
  print -u2 "This workflow needs macOS 26 or newer (found $(sw_vers -productVersion))."
  print -u2 "TranslationSession(installedSource:target:) does not exist on earlier releases."
  exit 1
fi

build() {
  print "Building $BIN ..."
  local arm=build/offtranslate-arm64 intel=build/offtranslate-x86_64
  mkdir -p build workflow

  swiftc -O -parse-as-library -target "arm64-apple-macos${DEPLOY_TARGET}" "$SRC" -o "$arm"

  # Intel slice is best-effort: build it when the SDK can, ship arm64-only otherwise.
  if swiftc -O -parse-as-library -target "x86_64-apple-macos${DEPLOY_TARGET}" "$SRC" -o "$intel" 2>/dev/null; then
    lipo -create "$arm" "$intel" -output "$BIN"
    print "  universal (arm64 + x86_64)"
  else
    cp "$arm" "$BIN"
    print "  arm64 only (x86_64 slice unavailable on this SDK)"
  fi
  chmod +x "$BIN"
  rm -rf build
}

check() {
  print "\n--- Language availability ---"
  "$BIN" --list
  local pair=${OFFTRANSLATE_PAIR:-en,pl}
  local a=${pair%%,*} b=${pair##*,}
  print "\n--- Default pair ($a <-> $b) ---"
  local ok=1
  for dir in "$a $b" "$b $a"; do
    local from=${dir%% *} to=${dir##* }
    if out=$("$BIN" --plain --from "$from" --to "$to" "test" 2>&1); then
      print "  $from -> $to  ready"
    else
      print "  $from -> $to  NOT READY: $out"
      ok=0
    fi
  done
  (( ok )) || {
    print "\nDownload the missing language in System Settings > General > Language & Region >"
    print "Translation Languages, then run ./build.sh --check again."
    exit 1
  }
  print "\nBoth directions work offline."
}

package() {
  local out="$NAME.alfredworkflow"
  rm -f "$out"
  (cd workflow && zip -q -r -X "../$out" . -x '.*')
  print "Packaged $out ($(du -h "$out" | cut -f1))"
  print "Double-click it to install, or run: open \"$out\""
}

build
case "${1:-}" in
  --check) check ;;
  --package) package ;;
  "") ;;
  *) print -u2 "Unknown option: $1"; exit 2 ;;
esac
