#!/usr/bin/env bash
# Scenario 3 driver - parent sets NEITHER override (clean launch).
# Runs in ONE product-session shell (the primary's tool shell).
set -u
WT='__WT__'
LAB='__LAB__'
EF='__EF__'
CRE="$WT/bin/fm-crew-state.sh"
SNAP="$WT/bin/fm-fleet-snapshot.sh"
ok()  { printf 'RESULT ok|%s\n' "$1"; }
bad() { printf 'RESULT bad|%s\n' "$1"; }
section() { printf '== %s ==\n' "$1"; }

{
section "s3: session shell initial env (clean launch - neither override set)"
if [ -z "${FM_CREW_STATE_META_OVERRIDE+set}" ]; then
  ok "meta-override-absent-at-launch"
else
  bad "meta-override-present-at-launch: $FM_CREW_STATE_META_OVERRIDE"
fi
if [ -z "${FM_CREW_STATE_STATUS_OVERRIDE+set}" ]; then
  ok "status-override-absent-at-launch"
else
  bad "status-override-present-at-launch: $FM_CREW_STATE_STATUS_OVERRIDE"
fi

section "s3: default crew-state read (live state path, live status log)"
OUT1=$("$CRE" leaktask 2>&1)
printf 's3: %s\n' "$OUT1"
case "$OUT1" in
  'state: blocked · source: status-log · live-status-default-note')
    ok "default-live-read-blocked-status-log" ;;
  *) bad "default-read: expecting live 'blocked · status-log · live-status-default-note', got: $OUT1" ;;
esac

section "s3: fleet snapshot run as a command in the session shell"
if "$SNAP" --json > "$EF/s3-snapshot-command.json" 2>"$EF/s3-snapshot-command.err"; then
  ok "snapshot-command-ran"
else
  bad "snapshot-command-failed rc=$?"
fi
SNAPLINE=$(jq -c '.tasks[] | select(.id=="leaktask") | .current_state.raw' "$EF/s3-snapshot-command.json" 2>&1)
printf 's3: snapshot current_state for leaktask: %s\n' "$SNAPLINE"
case "$SNAPLINE" in
  '"state: blocked · source: status-log · live-status-default-note"')
    ok "snapshot-default-behavior-unchanged" ;;
  *) bad "snapshot-current-state-unexpected: $SNAPLINE" ;;
esac

section "s3: session shell env after command-run snapshot"
if [ -z "${FM_CREW_STATE_META_OVERRIDE+set}" ]; then
  ok "meta-override-still-absent-after-command-run"
else
  bad "meta-override-appeared-after-command-run: $FM_CREW_STATE_META_OVERRIDE"
fi
if [ -z "${FM_CREW_STATE_STATUS_OVERRIDE+set}" ]; then
  ok "status-override-still-absent-after-command-run"
else
  bad "status-override-appeared-after-command-run: $FM_CREW_STATE_STATUS_OVERRIDE"
fi

section "s3: fleet snapshot SOURCED into the session shell"
. "$SNAP" --json >/dev/null 2>>"$EF/s3-snapshot-command.err"
SRC_RC=$?
printf 's3: source rc=%s\n' "$SRC_RC"
ok "session-shell-survived-sourcing"

section "s3: session shell env after sourced snapshot (the poison window)"
if [ -z "${FM_CREW_STATE_META_OVERRIDE+set}" ]; then
  ok "meta-override-still-absent-after-source"
else
  bad "meta-override-appeared-after-source: $FM_CREW_STATE_META_OVERRIDE"
fi
if [ -z "${FM_CREW_STATE_STATUS_OVERRIDE+set}" ]; then
  ok "status-override-still-absent-after-source"
else
  bad "status-override-appeared-after-source: $FM_CREW_STATE_STATUS_OVERRIDE"
fi

section "s3: default crew-state read after snapshot runs (default behavior unchanged)"
OUT2=$("$CRE" leaktask 2>&1)
printf 's3: %s\n' "$OUT2"
if [ "$OUT2" = "$OUT1" ]; then
  ok "post-snapshot-read-identical-to-pre-snapshot-read"
else
  bad "post-snapshot-read-changed: pre='$OUT1' post='$OUT2'"
fi

section "s3: rewrite the LIVE status log; the session read must see the live value"
printf 'failed: live-path-rewrite-proof\n' > "$LAB/state/leaktask.status"
OUT3=$("$CRE" leaktask 2>&1)
printf 's3: %s\n' "$OUT3"
case "$OUT3" in
  'state: failed · source: status-log · live-path-rewrite-proof')
    ok "live-status-rewrite-visible (no stale override poisons the session)" ;;
  *) bad "post-rewrite-read: expecting live 'failed · status-log · live-path-rewrite-proof', got: $OUT3" ;;
esac
} > "$EF/s3-out.txt" 2>&1
printf 'SCENARIO3_DONE\n' | tee -a "$EF/s3-out.txt"
cat "$EF/s3-out.txt"
exit 0
