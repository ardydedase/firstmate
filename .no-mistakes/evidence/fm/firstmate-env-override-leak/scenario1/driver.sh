#!/usr/bin/env bash
# Scenario 1 driver - parent sets FM_CREW_STATE_META_OVERRIDE only.
# Runs in ONE product-session shell (the primary's tool shell): the fleet
# snapshot is run as a command and then sourced into this same shell, and the
# session-owned override value plus the shadow-override crew-state read are
# observed across both forms.
set -u
WT='/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XHTF5DAY4XYNGXRNTA9BB4'
LAB='/var/folders/rz/f8b2_npd0tjf2624px5jw_980000gn/T//fm-lab.WDPoG7'
EF='/Users/adedase/.no-mistakes/evidence/01M5XHTF5DAY4XYNGXRNTA9BB4/scenario1'
CRE="$WT/bin/fm-crew-state.sh"
SNAP="$WT/bin/fm-fleet-snapshot.sh"
SHADOW_META="$LAB/shadow/leaktask.meta"
ok()  { printf 'RESULT ok|%s\n' "$1"; }
bad() { printf 'RESULT bad|%s\n' "$1"; }
section() { printf '== %s ==\n' "$1"; }

{
section "s1: session shell initial env (inherited from parent at launch)"
if [ "${FM_CREW_STATE_META_OVERRIDE:-}" = "$SHADOW_META" ]; then
  ok "meta-override-inherited-from-parent-launch: $FM_CREW_STATE_META_OVERRIDE"
else
  bad "meta-override-at-launch: got '${FM_CREW_STATE_META_OVERRIDE:-<unset>}' want '$SHADOW_META'"
fi
if [ -z "${FM_CREW_STATE_STATUS_OVERRIDE+set}" ]; then
  ok "status-override-absent-at-launch"
else
  bad "status-override-present-at-launch: $FM_CREW_STATE_STATUS_OVERRIDE"
fi

section "s1: crew-state read consults the parent META override (override takes effect)"
OUT1=$("$CRE" leaktask 2>&1)
printf 's1: %s\n' "$OUT1"
case "$OUT1" in
  'state: unknown · source: none · worktree gone (torn down?)')
    ok "meta-override-drives-crew-state-read" ;;
  *) bad "meta-override-crew-state-read: expecting shadow-meta verdict 'worktree gone (torn down?)', got: $OUT1" ;;
esac

section "s1: fleet snapshot run as a command in the session shell"
if "$SNAP" --json > "$EF/s1-snapshot-command.json" 2>"$EF/s1-snapshot-command.err"; then
  ok "snapshot-command-ran"
else
  bad "snapshot-command-failed rc=$?"
fi
SNAPLINE=$(jq -c '.tasks[] | select(.id=="leaktask") | .current_state.raw' "$EF/s1-snapshot-command.json" 2>&1)
printf 's1: snapshot current_state for leaktask: %s\n' "$SNAPLINE"
case "$SNAPLINE" in
  '"state: blocked · source: status-log · live-status-default-note"')
    ok "snapshot-uses-captured-meta-not-ambient-override" ;;
  *) bad "snapshot-current-state-unexpected: $SNAPLINE" ;;
esac

section "s1: session shell env after command-run snapshot"
if [ "${FM_CREW_STATE_META_OVERRIDE:-}" = "$SHADOW_META" ]; then
  ok "meta-override-unchanged-after-command-run: $FM_CREW_STATE_META_OVERRIDE"
else
  bad "meta-override-changed-after-command-run: '${FM_CREW_STATE_META_OVERRIDE:-<unset>}'"
fi
if [ -z "${FM_CREW_STATE_STATUS_OVERRIDE+set}" ]; then
  ok "status-override-still-absent-after-command-run"
else
  bad "status-override-appeared-after-command-run: $FM_CREW_STATE_STATUS_OVERRIDE"
fi

section "s1: fleet snapshot SOURCED into the session shell"
. "$SNAP" --json >/dev/null 2>>"$EF/s1-snapshot-command.err"
SRC_RC=$?
printf 's1: source rc=%s\n' "$SRC_RC"
ok "session-shell-survived-sourcing"

section "s1: session shell env after sourced snapshot (the poison window)"
if [ "${FM_CREW_STATE_META_OVERRIDE:-}" = "$SHADOW_META" ]; then
  ok "meta-override-unchanged-after-source (no captured-path leak): $FM_CREW_STATE_META_OVERRIDE"
else
  bad "meta-override-CHANGED-after-source (leak): '${FM_CREW_STATE_META_OVERRIDE:-<unset>}'"
fi
if [ -z "${FM_CREW_STATE_STATUS_OVERRIDE+set}" ]; then
  ok "status-override-still-absent-after-source"
else
  bad "status-override-appeared-after-source: $FM_CREW_STATE_STATUS_OVERRIDE"
fi

section "s1: crew-state read after snapshot runs (caller-owned override still steering)"
OUT2=$("$CRE" leaktask 2>&1)
printf 's1: %s\n' "$OUT2"
case "$OUT2" in
  'state: unknown · source: none · worktree gone (torn down?)')
    ok "crew-state-read-still-uses-parent-override" ;;
  *) bad "crew-state-read-after-snapshot: expecting shadow verdict again, got: $OUT2" ;;
esac
} > "$EF/s1-out.txt" 2>&1
printf 'SCENARIO1_DONE\n' | tee -a "$EF/s1-out.txt"
cat "$EF/s1-out.txt"
exit 0
