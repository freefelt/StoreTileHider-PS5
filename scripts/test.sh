#!/usr/bin/env bash
# Runs the tests. They run the program on this machine with the paths moved to /tmp (no root, no console). Prepare once:
# tests/setup-env.sh (Linux: packages), then tests/build/build-test-binaries.sh (repeat after changes in src/).
#
#   scripts/test.sh list                     the areas and their suites
#   scripts/test.sh smoke                    a quick check (3 suites)
#   scripts/test.sh full                     all suites (about 1 minute)
#   scripts/test.sh <area>...                toggle, safety, real
#   scripts/test.sh suite <test_x.py>...     single suites by file name, e.g. suite test_backup.py
# Results: /tmp/sth-test-suites.txt (a line per suite), /tmp/sth-test-timing.txt, /tmp/sth-test-<suite>.out (the output of each suite).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SUITES="$ROOT/tests/suites"
# the suites of an area (a function, not an associative array: this runs on the bash 3.2 of macOS too)
area_suites() {
    case "$1" in
        toggle) echo "toggle/test_toggle.py" ;;
        safety) echo "safety/test_backup.py safety/test_rollback_and_busy.py" ;;
        real)   echo "real/test_real_dump.py" ;;
        smoke)  echo "toggle/test_toggle.py safety/test_backup.py safety/test_rollback_and_busy.py" ;;
        *)      return 1 ;;
    esac
}
AREAS="toggle safety real"
TMO=""   # a limit per suite where `timeout` exists (Linux; on macOS: brew install coreutils gives gtimeout)
if command -v timeout >/dev/null 2>&1; then TMO="timeout 300"; elif command -v gtimeout >/dev/null 2>&1; then TMO="gtimeout 300"; fi

run_suites() {   # relative suite paths...; returns 1 if any suite failed (a failed check, a crash or a timeout)
    local res=/tmp/sth-test-suites.txt tim=/tmp/sth-test-timing.txt failed=0
    : > "$res"; : > "$tim"
    [ -x "$ROOT/.deps/test/out/StoreTileHider_host" ] || { echo "the test programs are not built: run tests/build/build-test-binaries.sh"; return 2; }
    for t in "$@"; do
        local name; name="$(basename "$t" .py)"
        local t0 t1 rc; t0=$(date +%s)
        $TMO python3 -u "$SUITES/$t" > "/tmp/sth-test-$name.out" 2>&1; rc=$?
        t1=$(date +%s)
        echo "$name: $(grep -E 'checks passed' "/tmp/sth-test-$name.out") (exit $rc, FAIL lines: $(grep -c '^FAIL' "/tmp/sth-test-$name.out"))" >> "$res"
        echo "$((t1 - t0)) $name" >> "$tim"
        if [ "$rc" -ne 0 ] || ! grep -q 'checks passed' "/tmp/sth-test-$name.out" || grep -q '^FAIL' "/tmp/sth-test-$name.out"; then
            failed=1
            # what failed, right under the summary line (on a CI runner the .out file is not at hand), and the end of the output if the suite did not finish
            grep '^FAIL' "/tmp/sth-test-$name.out" | cut -c1-600 | sed 's/^/    /' >> "$res"
            grep -q 'checks passed' "/tmp/sth-test-$name.out" || tail -12 "/tmp/sth-test-$name.out" | cut -c1-300 | sed 's/^/    | /' >> "$res"
        fi
    done
    echo "--- seconds per suite, the slowest first (total $(awk '{s+=$1} END {print s}' "$tim") s):" >> "$res"
    sort -rn "$tim" | head -10 >> "$res"
    echo "ALL DONE" >> "$res"
    cat "$res"
    return $failed
}

cmd="${1:-list}"
case "$cmd" in
    list)
        for a in $AREAS smoke; do echo "$a: $(area_suites "$a")"; done
        echo "full: all the suites of the areas above"; exit 0 ;;
    suite)
        shift; list=()
        for n in "$@"; do f="$(cd "$SUITES" && find . -name "$n" | head -1)"; [ -n "$f" ] || { echo "no such suite: $n"; exit 2; }; list+=("${f#./}"); done
        run_suites "${list[@]}"; exit $? ;;
    *)
        list=""
        for a in "$@"; do
            if [ "$a" = full ]; then list=""; for x in $AREAS; do list="$list $(area_suites "$x")"; done; break; fi
            area_suites "$a" >/dev/null || { echo "no such area: $a (scripts/test.sh list)"; exit 2; }
            list="$list $(area_suites "$a")"
        done
        run_suites $(echo $list | tr ' ' '\n' | awk '!seen[$0]++'); exit $? ;;
esac
