#!/bin/bash
# Run the GUT suites under test/gut and report the result.
#
#   test/run_gut.sh                        every GUT suite
#   test/run_gut.sh catch_chance_test.gd   just that file
#
# GUT is a second harness running alongside test/run.sh, which still owns the
# `extends SceneTree` suites in test/. Two things it does that run.sh cannot:
#
# 1. An engine error inside a test is a test failure, not a line of output
#    that a grep has to notice. run.sh spots one only because it greps for
#    SCRIPT ERROR; the underlying godot run exits 0 and prints FAILURES=0.
# 2. A GUT script loads at runtime, after autoloads register, so it can name
#    `Inventory`, `Party`, `Hud` and `Tuning` directly. A `-s` script cannot:
#    it fails to compile before any code runs.
#
# Two flags that are not optional:
#
#   No -d. It attaches the debugger, and an error then drops the run into an
#   interactive `debug>` prompt that waits forever.
#   -gprefix= -gsuffix=_test.gd. GUT looks for `test_*.gd` by default and this
#   project names suites `*_test.gd`, so without these it finds nothing and
#   reports "Nothing was run" while exiting 0.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SELECT="${1:-}"
OUT="${TMPDIR:-/tmp}/mini-pals-tests"
mkdir -p "$OUT"
log="$OUT/gut.txt"
LIMIT=300

args=(-gdir=res://test/gut -ginclude_subdirs -gprefix= -gsuffix=_test.gd -gexit)
[ -n "$SELECT" ] && args+=("-gselect=$SELECT")

# There is no `timeout` binary on macOS, hence perl. Redirect rather than pipe,
# since a pipe hides the failing line.
perl -e 'alarm shift; exec @ARGV' "$LIMIT" \
    godot --headless -s addons/gut/gut_cmdln.gd "${args[@]}" \
    < /dev/null > "$log" 2>&1
status=$?

# An absent summary is a died or timed-out run, which is not a pass. GUT also
# exits 0 when its filters match no script at all, so that counts as a failure
# here: asking for a suite and silently running none is how a green lies.
if ! /usr/bin/grep -qE '^Passing Tests' "$log"; then
    echo "NO RESULT (died, matched nothing, or hit the ${LIMIT}s limit)"
    echo "Log in $log"
    exit 1
fi

/usr/bin/grep -A 12 '^Totals' "$log"

if [ "$status" != "0" ]; then
    echo
    echo "GUT reported failures. Log in $log"
    exit 1
fi
echo
echo "All green. Log in $log"
