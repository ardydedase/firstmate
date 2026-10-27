#!/usr/bin/env bash
# Scenario 2 driver - parent sets FM_CREW_STATE_STATUS_OVERRIDE only.
# Runs in ONE product-session shell (the primary's tool shell): the fleet
# snapshot is run as a command and then sourced into this same shell, and the
# session-owned override value plus the shadow-override crew-state read are
# observed across both forms.
set -u
WT='__WT__'
LAB='__LAB__'
EF='__EF__'
CRE="$WT/bin/fm-crew-state.sh"
SNAP="$WT/bin/fm-fleet-snapshot.sh"
SHADOW_STATUS="$LAB/shadow/leaktask.status"
ok()  { printf 'RESULT ok|%s\n' "$1"; }
bad() { printf 'RESULT bad|%s\n' "$1"; }
section() { printf '== %s ==\n' "$1"; }

{
section "s2: session shell initial env (inherited from parent at launch)"
if [ -z "${FM_CREW_STATE_META_OVERRIDE+set}" ]; then
  ok "meta-override-absent-at-launch"
else
  bad "meta-override-present-at-launch: $FM_CREW_STATE_META_OVERRIDE"
fi
if [ "${FM_CREW_STATE_STATUS_OVERRIDE:-}" = "$SHADOW_STATUS" ]; then
  ok "status-override-inherited-from-parent-launch: $FM_CREW_STATE_STATUS_OVERRIDE"
else
  bad "status-override-at-launch: got '${FM_CREW_STATE_STATUS_OVERRIDE:-<unset>}' want '$SHADOW_STATUS'"
fi

section "s2: crew-state read consults the parent STATUS override (override takes effect)"
OUT1=$("$CRE" leaktask 2>&1)
printf 's2: %s\n' "$OUT1"
case "$OUT1" in
  'state: blocked · source: status-log · parent-status-override-note')
    ok "status-override-drives-crew-state-read" ;;
  *) bad "status-override-crew-state-read: expecting shadow note 'parent-status-override-note', got: $OUT1" ;;
esac

section "s2: fleet snapshot run as a command in the session shell"
if "$SNAP" --json > "$EF/s2-snapshot-command.json" 2>"$EF/s2-snapshot-command.err"; then
  ok "snapshot-command-ran"
else
  bad "snapshot-command-failed rc=$?"
fi
SNAPLINE=$(jq -c '.tasks[] | select(.id=="leaktask") | .current_state.raw' "$EF/s2-snapshot-command.json" 2>&1)
printf 's2: snapshot current_state for leaktask: %s\n' "$SNAPLINE"
case "$SNAPLINE" in
  '"state: blocked · source: status-log · live-status-default-note"')
    ok "snapshot-uses-captured-status-not-ambient-override" ;;
  *) bad "snapshot-current-state-unexpected: $SNAPLINE" ;;
esac

section "s2: session shell env after command-run snapshot"
if [ -z "${FM_CREW_STATE_META_OVERRIDE+set}" ]; then
  ok "meta-override-still-absent-after-command-run"
else
  bad "meta-override-appeared-after-command-run: $FM_CREW_STATE_META_OVERRIDE"
fi
if [ "${FM_CREW_STATE_STATUS_OVERRIDE:-}" = "$SHADOW_STATUS" ]; then
  ok "status-override-unchanged-after-command-run: $FM_CREW_STATE_STATUS_OVERRIDE"
else
  bad "status-override-changed-after-command-run: '${FM_CREW_STATE_STATUS_OVERRIDE:-<unset>}'"
fi

section "s2: fleet snapshot SOURCED into the session shell"
. "$SNAP" --json >/dev/null 2>>"$EF/s2-snapshot-command.err"
SRC_RC=$?
printf 's2: source rc=%s\n' "$SRC_RC"
ok "session-shell-survived-sourcing"

section "s2: session shell env after sourced snapshot (the poison window)"
if [ -z "${FM_CREW_STATE_META_OVERRIDE+set}" ]; then
  ok "meta-override-still-absent-after-source"
else
  bad "meta-override-appeared-after-source: $FM_CREW_STATE_META_OVERRIDE"
fi
if [ "${FM_CREW_STATE_STATUS_OVERRIDE:-}" = "$SHADOW_STATUS" ]; then
  ok "status-override-unchanged-after-source (no captured-path leak): $FM_CREW_STATE_STATUS_OVERRIDE"
else
  bad "status-override-CHANGED-after-source (leak): '${FM_CREW_STATE_STATUS_OVERRIDE:-<unset>}'"
fi

section "s2: crew-state read after snapshot runs (caller-owned override still steering)"
OUT2=$("$CRE" leaktask 2>&1)
printf 's2: %s\n' "$OUT2"
case "$OUT2" in
  'state: blocked · source: status-log · parent-status-override-note')
    ok "crew-state-read-still-uses-parent-override" ;;
  *) bad "crew-state-read-after-snapshot: expecting shadow note again, got: $OUT2" ;;
esac
} > "$EF/s2-out.txt" 2>&1
printf 'SCENARIO2_DONE\n' | tee -a "$EF/s2-out.txt"
cat "$EF/s2-out.txt"
exit 0
