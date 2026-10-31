#!/usr/bin/env bash
# Prepares a machine for the tests. The tests are light: they need clang, Python 3 with its sqlite3 module and SQLite; they write only to /tmp
# and need no root (the PS5 build itself needs none of this). On Ubuntu this script installs the packages (needs root); on macOS there is nothing to install
# (clang and SQLite come with the Xcode command line tools).
#   sudo tests/setup-env.sh
set -euo pipefail
case "$(uname -s)" in
    Linux)
        [ "$(id -u)" = 0 ] || { echo "ERROR: root is needed to install packages: sudo $0" >&2; exit 1; }
        apt-get update
        apt-get install -y --no-install-recommends clang-18 lld-18 llvm-18-dev make curl unzip python3 libsqlite3-dev build-essential
        ;;
    Darwin)
        echo "macOS: nothing to install (clang and SQLite come with the Xcode command line tools; for the PS5 build ./build.sh installs llvm@18 with Homebrew)."
        ;;
    *) echo "ERROR: the tests run on Linux and macOS" >&2; exit 1 ;;
esac
echo "Done. Check the machine with: tests/check-env.sh"
