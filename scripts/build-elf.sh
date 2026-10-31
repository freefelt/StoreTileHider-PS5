#!/usr/bin/env bash
# Step 2: SQLite + the program  ->  build/StoreTileHider-<version>.elf
# Run after scripts/deps.sh (needs the SDK and the SQLite source from .deps). Normally you run ./build.sh in the repository root instead.
#
#   scripts/build-elf.sh            # build everything (idempotent)
#   scripts/build-elf.sh --no-brew  # do not call brew install (macOS)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SRCDIR="$REPO/src"
VERSION="$(tr -d '[:space:]' <"$REPO/VERSION")"
# A test build handed out between releases: STH_DEBUG=N ./build.sh. The notification and last-run.log then say "0.1 debug N" (two builds of one version can be told apart);
# the name of the file stays StoreTileHider-<VERSION>.elf. Releases (CI) never set it.
STH_VER="$VERSION${STH_DEBUG:+ debug $STH_DEBUG}"
DEPS="$REPO/.deps"
BUILD="$DEPS/build"
SDK_DIR="$DEPS/ps5-payload-sdk"
SQLITE_DIR="$DEPS/sqlite"
OUT="$REPO/build"                  # the final ELF: build/StoreTileHider-<version>.elf
ELF="$OUT/StoreTileHider-$VERSION.elf"

USE_BREW=1
[ "${1:-}" = "--no-brew" ] && USE_BREW=0

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
sha256_of() {
    if have shasum; then shasum -a 256 "$1" | awk '{print $1}'
    else sha256sum "$1" | awk '{print $1}'; fi
}

mkdir -p "$BUILD" "$OUT"

# ---------- 1. Tools and environment ----------
say "Checking environment"
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
for t in curl tar make; do have "$t" || die "not found: $t"; done
[ -f "$SDK_DIR/toolchain/prospero.sh" ] || die "SDK not found. Run scripts/deps.sh first"
[ -f "$SQLITE_DIR/sqlite3.c" ] || die "SQLite source not found. Run scripts/deps.sh first"

# shellcheck disable=SC1091
source "$SDK_DIR/toolchain/prospero.sh"
SDK_VER="$(cat "$SDK_DIR/.sth-sdk-version" 2>/dev/null || echo unknown)" # shown in the notification and the log
[ "$SDK_VER" != unknown ] || die "the SDK folder has no version stamp (run scripts/deps.sh)"
printf 'SDK: %s\n' "$SDK_VER"

# ---------- 2. SQLite ----------
# built again when the SDK, the source or the flags change (the stamp records which object is here)
SQLITE_FLAGS="-DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION=1 -DSQLITE_OMIT_SHARED_CACHE=1 -DSQLITE_OMIT_WAL=1 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_MAX_MMAP_SIZE=0 -DSQLITE_TEMP_STORE=3 -DSQLITE_OMIT_DEPRECATED=1 -DSQLITE_DQS=0 -DSQLITE_OMIT_PROGRESS_CALLBACK=1 -DSQLITE_OMIT_TRACE=1"
SQLITE_ID="sdk:$SDK_VER src:$(sha256_of "$SQLITE_DIR/sqlite3.c") flags:$SQLITE_FLAGS"
if [ ! -f "$BUILD/sqlite3.o" ] || [ "$(cat "$BUILD/sqlite3.id" 2>/dev/null)" != "$SQLITE_ID" ]; then
    say "SQLite for the PS5"
    rm -f "$BUILD/sqlite3.o" "$BUILD/sqlite3.id"
    "$CC" -Os $SQLITE_FLAGS -c "$SQLITE_DIR/sqlite3.c" -o "$BUILD/sqlite3.o" >"$BUILD/sqlite.log" 2>&1 || { tail -30 "$BUILD/sqlite.log"; die "SQLite build failed (log: $BUILD/sqlite.log)"; }
    printf '%s\n' "$SQLITE_ID" >"$BUILD/sqlite3.id"
else
    say "SQLite: already built"
fi

# ---------- 3. The program ----------
say "StoreTileHider-$VERSION.elf"
rm -f "$OUT"/StoreTileHider-*.elf
: >"$BUILD/link.log"
"$CC" -Os -Wall -Wextra -DSTH_VERSION="\"$STH_VER\"" -DSTH_SDK_VERSION="\"$SDK_VER\"" -I"$SQLITE_DIR" -I"$SRCDIR" \
    -o "$ELF" "$SRCDIR/main.c" "$SRCDIR/store_tiles.c" "$BUILD/sqlite3.o" >>"$BUILD/link.log" 2>&1 \
    || { cat "$BUILD/link.log"; die "building the ELF failed"; }
grep -E "warning|error" "$BUILD/link.log" && die "warnings or errors (see $BUILD/link.log)" || true
"$STRIP" --strip-debug "$ELF"
# the ids of both tiles, the version and the SDK version have to be inside: otherwise the build would silently hand out the wrong file
for needle in NPXS40047 NPXS40056 "$STH_VER" "$SDK_VER"; do
    grep -aq -- "$needle" "$ELF" || die "the ELF does not contain \"$needle\""
done
printf 'Built: %s (%s bytes, SHA-256 %s)\n' "$ELF" "$(wc -c <"$ELF" | tr -d ' ')" "$(sha256_of "$ELF")"
printf '\nSend the file to the ELF loader of the console (port 9021); the result comes as a notification and the program ends by itself.\n'
