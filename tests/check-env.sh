#!/usr/bin/env bash
# Checks the machine for the tests (Linux or macOS, no root needed). Prints a table OK / WARNING / ERROR; exit code 1 on errors.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
bad=0
ok()   { printf '  %-44s OK      %s\n' "$1" "${2:-}"; }
warn() { printf '  %-44s WARNING %s\n' "$1" "${2:-}"; }
err()  { printf '  %-44s ERROR   %s\n' "$1" "${2:-}"; bad=1; }
have() { command -v "$1" >/dev/null 2>&1; }
echo "== system"
case "$(uname -s)" in
    Linux) ok "Linux ($(uname -m))" ;;
    Darwin) ok "macOS ($(uname -m))" "(Ubuntu 24.04 is what the tests are checked on)" ;;
    *) err "$(uname -s)" "the tests run on Linux and macOS" ;;
esac
echo "== tools"
for c in python3 bash tar curl; do have "$c" && ok "$c" "$($c --version 2>&1 | head -1 | cut -c1-60)" || err "$c" "not found"; done
if have clang-18; then ok "clang-18" "$(clang-18 --version 2>&1 | head -1 | cut -c1-60)"
elif have clang; then warn "clang" "clang-18 is what the payload is built with; any clang works for the tests"
else err "clang" "not found"; fi
python3 -c 'import sqlite3' 2>/dev/null && ok "python3 sqlite3 module" "SQLite $(python3 -c 'import sqlite3; print(sqlite3.sqlite_version)')" || err "python3 sqlite3 module" "missing"
if [ -f "$ROOT/.deps/sqlite/sqlite3.c" ]; then ok "SQLite source (.deps/sqlite)" "the pinned one"
elif [ -f /usr/include/sqlite3.h ] || printf '#include <sqlite3.h>\nint main(void){return 0;}\n' | "$(command -v clang-18 || command -v clang)" -x c - -lsqlite3 -o /dev/null 2>/dev/null; then ok "system SQLite (header and library)"
else err "SQLite" "neither .deps/sqlite (scripts/deps.sh) nor libsqlite3-dev (tests/setup-env.sh)"; fi
echo "== builds"
[ -x "$ROOT/.deps/test/out/StoreTileHider_host" ] && ok ".deps/test/out/StoreTileHider_host" || warn ".deps/test/out/StoreTileHider_host" "missing: tests/build/build-test-binaries.sh"
echo; [ "$bad" = 0 ] && echo "The machine is ready." || echo "There are errors: fix them and run the check again."
exit "$bad"
