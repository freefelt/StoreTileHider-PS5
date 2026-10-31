#!/usr/bin/env bash
# Builds the program the tests run, for THIS machine (Linux or macOS): the same sources as the payload, with the paths moved to /tmp.
#   tests/build/build-test-binaries.sh   ->  .deps/test/out/StoreTileHider_host
# Needs clang (clang-18 is preferred) and SQLite: the pinned source in .deps/sqlite (scripts/deps.sh) or the system library (libsqlite3-dev).
# Run it again after every change in src/.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
CC="$(command -v clang-18 || command -v clang)" || { echo "ERROR: clang not found" >&2; exit 1; }
mkdir -p "$TEST_BUILD" "$OUT"
if [ -f "$SQLITE_DIR/sqlite3.c" ]; then
    FLAGS="-DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION=1 -DSQLITE_OMIT_SHARED_CACHE=1 -DSQLITE_OMIT_WAL=1 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_MAX_MMAP_SIZE=0 -DSQLITE_TEMP_STORE=3 -DSQLITE_OMIT_DEPRECATED=1 -DSQLITE_DQS=0"
    [ -f "$TEST_BUILD/sqlite3_host.o" ] && [ "$TEST_BUILD/sqlite3_host.o" -nt "$SQLITE_DIR/sqlite3.c" ] || "$CC" -O2 $FLAGS -c "$SQLITE_DIR/sqlite3.c" -o "$TEST_BUILD/sqlite3_host.o"
    SQL_INC="-I$SQLITE_DIR"; SQL_LIBS="$TEST_BUILD/sqlite3_host.o -lpthread -ldl -lm"
else
    echo "(.deps/sqlite not found: the system SQLite is used)"
    SQL_INC=""; SQL_LIBS="-lsqlite3"
fi
# shellcheck disable=SC2086
"$CC" -O2 -Wall -Wextra -Werror -DSTH_HOST_TEST -DSTH_VERSION='"test"' $SQL_INC -I"$SRCDIR" \
    "$SRCDIR/main.c" "$SRCDIR/store_tiles.c" $SQL_LIBS -o "$OUT/StoreTileHider_host"
echo "Built: $OUT/StoreTileHider_host"
