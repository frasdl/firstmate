#!/usr/bin/env bash
# Replicates tests/fm-wake-queue.test.sh:test_empty_actor_claims_leave_no_scratch_tmp_behind
# against a caller-selected bin/fm-wake-drain.sh (usage: script <worktree-root> <path-to-fm-wake-drain.sh> <label>).
set -u
ROOT=$1
DRAIN=$2
LABEL=$3

# shellcheck source=tests/wake-helpers.sh
. "$ROOT/tests/wake-helpers.sh"

GRANT="$ROOT/bin/fm-wake-grant.sh"
WDLIB="$ROOT/bin/fm-wake-lib.sh"

state=$(mktemp -d)/state
mkdir -p "$state"
AM=$(mktemp -d)  # anchor for FM_STATE_OVERRIDE root inference

append_wake() {
  local kind=$1 key=$2 payload=$3
  FM_STATE_OVERRIDE="$state" bash -c '. "$1"; fm_wake_append "$2" "$3" "$4"' _ "$WDLIB" "$kind" "$key" "$payload"
}

append_wake signal "task-a.status" "signal: task-a"
append_wake stale "fm-window" "stale: fm-window"
FM_STATE_OVERRIDE="$state" FM_ROOT_OVERRIDE="$AM" "$GRANT" activate "$$" empty-claims || exit 2
FM_STATE_OVERRIDE="$state" FM_ROOT_OVERRIDE="$AM" "$GRANT" publish empty-claims 1 2 || exit 2

FM_STATE_OVERRIDE="$state" FM_ROOT_OVERRIDE="$AM" "$DRAIN" > /dev/null 2> /dev/null || exit 3 # main drain: empty claim set
err=$(mktemp)
FM_STATE_OVERRIDE="$state" FM_ROOT_OVERRIDE="$AM" FM_SUPERVISION_ACTOR=branch "$DRAIN" 2> "$err" > /dev/null || exit 4
sequence=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9][0-9]*\) --recovery-generation [A-Za-z0-9._-][A-Za-z0-9._-]*$/\1/p' "$err")
generation=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through [0-9][0-9]* --recovery-generation \([A-Za-z0-9._-][A-Za-z0-9._-]*\)$/\1/p' "$err")
[ -n "$sequence" ] && [ -n "$generation" ] || exit 5
FM_STATE_OVERRIDE="$state" FM_ROOT_OVERRIDE="$AM" FM_SUPERVISION_ACTOR=branch "$DRAIN" --ack-through "$sequence" --recovery-generation "$generation" || exit 6

left=$(
  find "$state" -maxdepth 1 \( -name '.main-eligible-rows.tmp.*' -o -name '.wake-rows.consume.*' \) \
    -exec basename {} \; | LC_ALL=C sort
)
if [ -n "$left" ]; then
  printf '%s: left scratch tmp file(s) in state/: %s\n' "$LABEL" "$(echo "$left" | tr '\n' ' ')"
  exit 7
fi
printf '%s: no scratch tmp files left in state/\n' "$LABEL"
exit 0