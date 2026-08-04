#!/usr/bin/env bash
# Smoke tests for polaris-scan-result-check.py.
#
# The check ran for 13 months always exiting 1 because it read a hardcoded path
# instead of its argv, so these assert the exit codes for the cases we rely on.
#
# Usage: ./test-result-check.sh
set -uo pipefail

SCRIPT="$(dirname "$0")/polaris-scan-result-check.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# run <expected_exit> <name> <json> <total_threshold> <new_threshold>
run() {
  local expected="$1" name="$2" json="$3" total="$4" new="$5"
  local dir="$TMP/$RANDOM$RANDOM/polaris"
  mkdir -p "$dir"
  printf '%s' "$json" > "$dir/cli-scan.json"

  local out actual
  out="$(python3 "$SCRIPT" "$dir/cli-scan.json" "$total" "$new" 2>&1)"
  actual=$?

  if [ "$actual" -eq "$expected" ]; then
    printf 'ok   %-46s exit=%s\n' "$name" "$actual"
    pass=$((pass + 1))
  else
    printf 'FAIL %-46s expected=%s actual=%s\n' "$name" "$expected" "$actual"
    printf '       output: %s\n' "$out"
    fail=$((fail + 1))
  fi
}

# Shape per IssueSummaryV1 / CliScanV2: tools[].jobStatus, issueSummary.{total,summaryUrl}
clean='{"tools":[{"jobStatus":"COMPLETED"}],"issueSummary":{"total":0,"newIssues":0,"summaryUrl":"https://polaris.example/x"}}'
has_new='{"tools":[{"jobStatus":"COMPLETED"}],"issueSummary":{"total":7,"newIssues":3,"summaryUrl":"https://polaris.example/x"}}'
no_new_key='{"tools":[{"jobStatus":"COMPLETED"}],"issueSummary":{"total":4,"summaryUrl":"https://polaris.example/x"}}'
running='{"tools":[{"jobStatus":"RUNNING"}],"issueSummary":{"total":0,"newIssues":0,"summaryUrl":"https://polaris.example/x"}}'
no_tools='{"issueSummary":{"total":0,"newIssues":0,"summaryUrl":"https://polaris.example/x"}}'

echo "--- path handling (the 643-failure regression) ---"
run 0  "clean scan at caller-supplied path"       "$clean"   0 0
echo "--- gating ---"
run 5  "new issues with zero thresholds"          "$has_new" 0 0
run 20 "new issues over explicit threshold"       "$has_new" 0 2
run 0  "new issues under explicit threshold"      "$has_new" 0 5
run 30 "total issues over explicit threshold"     "$has_new" 3 0
echo "--- scan state / malformed input ---"
run 10 "scan not COMPLETED"                       "$running" 0 0
run 3  "missing tools section"                    "$no_tools" 0 0
run 2  "unparseable json"                         '{"tools":' 0 0

echo "--- missing newIssues key (undocumented field) ---"
run "${EXPECT_NO_NEW_KEY:-0}" "issueSummary without newIssues"  "$no_new_key" 0 0

# File-not-found needs no fixture; assert it reports cleanly rather than
# dying in a finally block with UnboundLocalError.
echo "--- missing file ---"
out="$(python3 "$SCRIPT" "$TMP/nope/cli-scan.json" 0 0 2>&1)"
actual=$?
if [ "$actual" -eq 1 ] && ! printf '%s' "$out" | grep -q UnboundLocalError; then
  printf 'ok   %-46s exit=1, clean message\n' "absent file reports cleanly"
  pass=$((pass + 1))
else
  printf 'FAIL %-46s exit=%s\n       output: %s\n' "absent file reports cleanly" "$actual" "$out"
  fail=$((fail + 1))
fi

echo
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
