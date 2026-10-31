#!/usr/bin/env bash
# Step 1: ps5-payload-sdk and the SQLite source for the PS5.
# Everything lives inside the project folder (.deps), without sudo and without touching ~/.zshrc.
#
# Usage:
#   scripts/deps.sh            # SDK + SQLite
#   scripts/deps.sh --no-brew  # do not call brew install (macOS)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEPS="$ROOT/.deps"
DL="$DEPS/dl"
SDK_DIR="$DEPS/ps5-payload-sdk"
SQLITE_DIR="$DEPS/sqlite"

SDK_VERSION="v0.45" # the latest release of the SDK (2026-10-21); v0.42 is the first with firmware 13.60 (the startup code of the SDK knows the firmware versions one by one), v0.45 also knows 14.00/14.10
SDK_URL="https://github.com/ps5-payload-dev/sdk/releases/download/${SDK_VERSION}/ps5-payload-sdk.zip"
SDK_SHA256="5fac64093d0e3e69f2584ce7935f24f703f622d9681f1495c85b9f00d1291a2c"

# SQLite 3.53.4 (the amalgamation, public domain) is taken from the npm package better-sqlite3 13.0.3
SQLITE_TGZ_URL="https://registry.npmjs.org/better-sqlite3/-/better-sqlite3-13.0.3.tgz"
SQLITE_TGZ_SHA256="77e0513dc1a469fb3bceec4c7fb5ad3f403109787eda05be047ec17fd56868cb"
SQLITE_C_SHA256="6a2805f8c1ef020a7086e62258519323cf98b219e9fe87a42065d916cfebaefc"
SQLITE_H_SHA256="919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d"

USE_BREW=1
[ "${1:-}" = "--no-brew" ] && USE_BREW=0

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

sha256_of() {
    if have shasum; then shasum -a 256 "$1" | awk '{print $1}'
    else sha256sum "$1" | awk '{print $1}'; fi
}

fetch() { # url file sha256
    local url="$1" file="$2" want="$3"
    if [ ! -f "$file" ]; then
        printf 'Downloading %s\n' "$(basename "$file")"
        curl --fail --location --retry 3 --silent --show-error "$url" --output "$file"
    fi
    local got; got="$(sha256_of "$file")"
    if [ "$got" != "$want" ]; then
        rm -f "$file"
        die "wrong SHA-256 for $(basename "$file")
  expected: $want
  got:      $got"
    fi
}

mkdir -p "$DL"

# ---------- 1. Host tools ----------
say "Checking tools"
case "$(uname -s)" in
    Darwin)
        if [ "$USE_BREW" -eq 1 ]; then
            have brew || die "Homebrew is required (https://brew.sh)"
            for f in llvm@18; do
                brew list --versions "$f" >/dev/null 2>&1 || brew install "$f"
            done
        fi
        LLVM_PREFIX="$(brew --prefix llvm@18 2>/dev/null || true)"
        [ -x "$LLVM_PREFIX/bin/llvm-config" ] || die "llvm@18 not found: brew install llvm@18"
        export LLVM_CONFIG="$LLVM_PREFIX/bin/llvm-config"
        ;;
    Linux)
        if have llvm-config-18; then export LLVM_CONFIG="$(command -v llvm-config-18)"
        elif have llvm-config; then export LLVM_CONFIG="$(command -v llvm-config)"
        else die "llvm-config is required (clang-18, lld-18, llvm-18-dev)"; fi
        ;;
    *) die "unsupported system: $(uname -s)" ;;
esac
for t in curl unzip tar make; do have "$t" || die "not found: $t"; done
printf 'LLVM: %s (%s)\n' "$LLVM_CONFIG" "$("$LLVM_CONFIG" --version)"

# ---------- 2. SDK ----------
# the stamp records which version is installed: a folder .deps from an older version must not keep the old SDK
if [ ! -f "$SDK_DIR/toolchain/prospero.sh" ] || [ "$(cat "$SDK_DIR/.sth-sdk-version" 2>/dev/null)" != "$SDK_VERSION" ]; then
    say "ps5-payload-sdk $SDK_VERSION"
    fetch "$SDK_URL" "$DL/ps5-payload-sdk-$SDK_VERSION.zip" "$SDK_SHA256"
    rm -rf "$DEPS/.sdk-extract"; mkdir -p "$DEPS/.sdk-extract"
    unzip -q "$DL/ps5-payload-sdk-$SDK_VERSION.zip" -d "$DEPS/.sdk-extract"
    [ -f "$DEPS/.sdk-extract/ps5-payload-sdk/toolchain/prospero.sh" ] || die "the SDK archive has no toolchain"
    rm -rf "$SDK_DIR"
    mv "$DEPS/.sdk-extract/ps5-payload-sdk" "$SDK_DIR"
    printf '%s\n' "$SDK_VERSION" >"$SDK_DIR/.sth-sdk-version"
    rmdir "$DEPS/.sdk-extract"
else
    say "SDK already installed: $SDK_DIR ($SDK_VERSION)"
fi

# ---------- 3. SQLite ----------
# the stamp records which source is installed (the sums of the two files)
SQLITE_ID="sqlite:$SQLITE_C_SHA256:$SQLITE_H_SHA256"
if [ ! -f "$SQLITE_DIR/sqlite3.c" ] || [ ! -f "$SQLITE_DIR/sqlite3.h" ] || [ "$(cat "$SQLITE_DIR/.sth-sqlite" 2>/dev/null)" != "$SQLITE_ID" ]; then
    say "SQLite 3.53.4 (the amalgamation from the npm package better-sqlite3 13.0.3)"
    fetch "$SQLITE_TGZ_URL" "$DL/better-sqlite3-13.0.3.tgz" "$SQLITE_TGZ_SHA256"
    rm -rf "$DEPS/.sqlite-extract" "$SQLITE_DIR"; mkdir -p "$DEPS/.sqlite-extract" "$SQLITE_DIR"
    tar xzf "$DL/better-sqlite3-13.0.3.tgz" -C "$DEPS/.sqlite-extract" package/deps/sqlite3/sqlite3.c package/deps/sqlite3/sqlite3.h
    [ "$(sha256_of "$DEPS/.sqlite-extract/package/deps/sqlite3/sqlite3.c")" = "$SQLITE_C_SHA256" ] || die "sqlite3.c: wrong SHA-256"
    [ "$(sha256_of "$DEPS/.sqlite-extract/package/deps/sqlite3/sqlite3.h")" = "$SQLITE_H_SHA256" ] || die "sqlite3.h: wrong SHA-256"
    cp "$DEPS/.sqlite-extract/package/deps/sqlite3/sqlite3.c" "$DEPS/.sqlite-extract/package/deps/sqlite3/sqlite3.h" "$SQLITE_DIR/"
    printf '%s\n' "$SQLITE_ID" >"$SQLITE_DIR/.sth-sqlite"
    rm -rf "$DEPS/.sqlite-extract"
else
    say "SQLite: already here"
fi

say "Done. SDK $SDK_VERSION and SQLite 3.53.4 are in $DEPS"
printf '\n%s\n' "Next: scripts/build-elf.sh (or just ./build.sh)"
