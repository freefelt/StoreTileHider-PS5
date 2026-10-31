# Paths shared by the test scripts (source this file).
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$BUILD_DIR/../.." && pwd -P)"
SRCDIR="$REPO/src"
TEST_BUILD="$REPO/.deps/test"                # the test binaries and the SQLite object for this machine
OUT="$TEST_BUILD/out"
SQLITE_DIR="$REPO/.deps/sqlite"              # the pinned SQLite source (scripts/deps.sh); if it is absent the system SQLite is used
VERSION="$(tr -d '[:space:]' <"$REPO/VERSION")"
