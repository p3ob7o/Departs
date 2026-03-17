#!/bin/bash
#
# TDD Loop — drives Claude through one test at a time
#
# Usage:
#   ./tdd-loop.sh                    # start from the beginning
#   ./tdd-loop.sh --resume 42        # resume from test #42
#   ./tdd-loop.sh --dry-run          # preview what would run
#
# Requirements:
#   - `claude` CLI installed and authenticated
#   - Run from the project root (where tdd-manifest.txt lives)
#
# Each iteration:
#   1. Feeds Claude a prompt for the next failing test
#   2. Claude implements minimum code to make it pass
#   3. Claude runs the full test suite to verify no regressions
#   4. Claude commits on success
#   5. Script moves to the next test
#

set -euo pipefail

MANIFEST="tdd-manifest.txt"
START_FROM=1
DRY_RUN=false

# ── Parse args ──
while [[ $# -gt 0 ]]; do
  case $1 in
    --resume)  START_FROM="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *)         echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ ! -f "$MANIFEST" ]]; then
  echo "Error: $MANIFEST not found. Run from project root."
  exit 1
fi

# ── Build test list (skip comments and blank lines) ──
TESTS=()
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  TESTS+=("$line")
done < "$MANIFEST"

TOTAL=${#TESTS[@]}
echo ""
echo "══════════════════════════════════════════════════"
echo "  TDD Loop — $TOTAL tests to implement"
echo "  Starting from test #$START_FROM"
echo "══════════════════════════════════════════════════"
echo ""

# ── Loop through each test ──
for (( i=START_FROM-1; i<TOTAL; i++ )); do
  LINE="${TESTS[$i]}"
  FILE=$(echo "$LINE" | cut -d'|' -f1 | xargs)
  TEST_NAME=$(echo "$LINE" | cut -d'|' -f2 | xargs)
  NUM=$((i + 1))

  echo "──────────────────────────────────────────────────"
  echo "  [$NUM/$TOTAL] $TEST_NAME"
  echo "  File: $FILE"
  echo "──────────────────────────────────────────────────"

  if $DRY_RUN; then
    echo "  (dry run — skipping)"
    echo ""
    continue
  fi

  # Build the prompt
  PROMPT=$(cat <<PROMPT_EOF
You are in a TDD loop. Your job is to make ONE test pass.

TARGET TEST:
  File: $FILE
  Test: "$TEST_NAME"

This is test $NUM of $TOTAL. All tests before this one should already be passing.

RULES:
1. Read the test file to understand what the test expects.
2. Implement ONLY the minimum source code needed to make this test pass.
3. Do NOT modify any test files (*.test.ts, *.test.tsx).
4. After implementing, run: npx vitest run
5. PASS CONDITION: The target test passes AND all previously passing tests still pass. Zero regressions.
6. If a previously passing test breaks, fix the regression before proceeding.
7. Once all tests pass (no regressions), commit:
   git add app/ && git commit -m "green: $TEST_NAME"

IMPORTANT:
- Minimum code only — do not implement anything beyond what this single test requires.
- If the test already passes without changes, just verify with npx vitest run and skip the commit.
PROMPT_EOF
  )

  # Invoke Claude
  echo "$PROMPT" | claude --continue -p --verbose

  EXIT_CODE=$?
  if [[ $EXIT_CODE -ne 0 ]]; then
    echo ""
    echo "⚠ Claude exited with code $EXIT_CODE on test $NUM."
    echo "  To resume: ./tdd-loop.sh --resume $NUM"
    exit $EXIT_CODE
  fi

  echo "  ✓ [$NUM/$TOTAL] $TEST_NAME"
  echo ""
done

echo ""
echo "══════════════════════════════════════════════════"
echo "  All $TOTAL tests implemented!"
echo "  Run 'npm run test:run' to verify."
echo "══════════════════════════════════════════════════"
