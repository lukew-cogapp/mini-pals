#!/bin/bash
# Run the headless suites and report anything Godot complained about.
#
#   test/run.sh            every suite
#   test/run.sh water      just the suites whose name contains "water"
#
# Two things this does that running godot by hand does not:
#
# 1. Bounds every run with a wall-clock timeout. A test awaiting something
#    that never fires hangs forever, and no GDScript harness stops it. There
#    is no `timeout` binary on macOS, hence perl.
# 2. Treats SCRIPT ERROR and parser warnings as failures. A script error
#    inside a test aborts that function but the suite still prints
#    FAILURES=0, so a green total on its own means nothing.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

FILTER="${1:-}"
OUT="${TMPDIR:-/tmp}/mini-pals-tests"
mkdir -p "$OUT"
LIMIT=240
fails=0
noisy=0

for suite in test/*_test.gd; do
    name=$(basename "$suite" _test.gd)
    [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]] && continue

    log="$OUT/$name.txt"
    printf '%-14s ' "$name"
    perl -e 'alarm shift; exec @ARGV' "$LIMIT" \
        env HOME=/private/tmp godot --headless --path . -s "$suite" \
        < /dev/null > "$log" 2>&1

    # An absent summary is a died or timed-out run, which is not a pass.
    if ! /usr/bin/grep -qE '^FAILURES=' "$log"; then
        echo "NO RESULT (died or hit the ${LIMIT}s limit)"
        fails=$((fails + 1))
        continue
    fi

    n=$(/usr/bin/grep -E '^FAILURES=' "$log" | tail -1 | cut -d= -f2)
    [ "$n" != "0" ] && fails=$((fails + n))

    # Leaked RIDs are the test not freeing nodes, not a fault. See CLAUDE.md.
    bad=$(/usr/bin/grep -cE 'SCRIPT ERROR|SHADOWED|CONFUSABLE|INTEGER_DIVISION|INT_AS_ENUM|UNUSED_' "$log")
    [ "$bad" != "0" ] && noisy=$((noisy + bad))

    printf 'FAILURES=%s' "$n"
    [ "$bad" != "0" ] && printf '  (%s script errors or warnings)' "$bad"
    echo
done

echo
if [ "$fails" != "0" ] || [ "$noisy" != "0" ]; then
    echo "$fails failed assertions, $noisy script errors or warnings."
    echo "Logs in $OUT"
    exit 1
fi
echo "All green, nothing logged. Logs in $OUT"
