#!/usr/bin/env bash
# drive-scenario.sh <1|2|3> <claude|probe> - launch a REAL product session on
# an isolated, disposable lab home (bin/fm-lab-home.sh) with a private tmux
# socket, carry the scenario's parent environment into the session, drive the
# scenario driver inside the session's shell (claude: through the primary's
# Bash tool; probe: through the session's interactive shell), capture the pane,
# and tear the whole lab down in this same evidence turn.
set -u
N=$1
MODE=$2
case "$N" in 1|2|3) ;; *) echo "usage: $0 <1|2|3> <claude|probe>"; exit 2 ;; esac
case "$MODE" in claude|probe) ;; *) echo "usage: $0 <1|2|3> <claude|probe>"; exit 2 ;; esac

WT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XHTF5DAY4XYNGXRNTA9BB4
EV=/Users/adedase/.no-mistakes/evidence/01M5XHTF5DAY4XYNGXRNTA9BB4
EF="$EV/scenario$N"
mkdir -p "$EF"

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX") || exit 1
printf '%s\n' "$LAB" > "$EF/lab-path.txt"
Cleanup() {
  "${CLEANENV[@]}" tmux -L fm-lab kill-server 2>/dev/null || true
  rm -rf "$LAB"
}
trap Cleanup EXIT
CLEANENV=(env -u NO_MISTAKES_GATE -u CLAUDE_CODE_ENABLE_TELEMETRY -u FM_GATE_REFUSE_BYPASS
  -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE
  -u FM_PROJECTS_OVERRIDE TMUX_TMPDIR="$LAB/tmux")

log() { printf '%s\n' "$*" >> "$EF/run-$MODE-log.txt"; }

log "== scenario $N ($MODE) lab=$LAB $(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "worktree HEAD: $(git -C "$WT" rev-parse HEAD) ($(git -C "$WT" branch --show-current))"

# --- disposable lab home + one-task fleet fixture ---------------------------
"$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null || { log "lab create failed"; exit 1; }
mkdir -p "$LAB/tmux" "$LAB/state" "$LAB/data" "$LAB/data/leaktask" "$LAB/projects/leaktask-wt"
cat > "$LAB/data/backlog.md" <<EOF2
## In flight
- [ ] leaktask - Leak Task data/leaktask/report.md (repo: alpha) (kind: scout) (since 2026-07-07)

## Done
EOF2
printf '# Report\n' > "$LAB/data/leaktask/report.md"
{
  printf '%s\n' "window=firstmate:fm-leaktask" "worktree=$LAB/projects/leaktask-wt" \
    "project=alpha" "harness=claude" "kind=scout" "mode=scout" "yolo=off"
} > "$LAB/state/leaktask.meta"
printf 'blocked: live-status-default-note\n' > "$LAB/state/leaktask.status"
# An idle busy verdict lets the crew-state read fall through to the live
# status log, so rewrites of that log stay observable in the session.
gen=$(FM_HOME="$LAB" "$WT/bin/fm-busy-event.sh" arm "$LAB/state" leaktask) || { log "busy arm failed"; exit 1; }
FM_HOME="$LAB" "$WT/bin/fm-busy-event.sh" apply "$LAB/state" leaktask idle \
  --gen "$gen" --source claude-hook --event stop >/dev/null || { log "busy apply failed"; exit 1; }
log "fixture: leaktask meta+status+idle busy verdict (gen=$gen) on lab home"

if [ "$N" != 3 ]; then
  mkdir -p "$LAB/shadow"
  {
    printf '%s\n' "window=firstmate:fm-leaktask" "worktree=$LAB/shadow/no-such-shadow-worktree" \
      "project=alpha" "harness=claude" "kind=ship" "mode=ship" "yolo=off"
  } > "$LAB/shadow/leaktask.meta"
  printf 'blocked: parent-status-override-note\n' > "$LAB/shadow/leaktask.status"
  log "parent environment will carry the shadow override for scenario $N"
fi

sed -e "s|__WT__|$WT|g" -e "s|__LAB__|$LAB|g" -e "s|__EF__|$EF|g" \
  "$EV/driver-s$N.template.sh" > "$EF/driver.sh"
chmod +x "$EF/driver.sh"

case "$N" in
  1) EFLAGS=(-e FM_HOME="$LAB" -e FM_CREW_STATE_META_OVERRIDE="$LAB/shadow/leaktask.meta") ;;
  2) EFLAGS=(-e FM_HOME="$LAB" -e FM_CREW_STATE_STATUS_OVERRIDE="$LAB/shadow/leaktask.status") ;;
  3) EFLAGS=(-e FM_HOME="$LAB") ;;
esac

# --- lab tmux: the task's crew window, then the product session primary ----
"${CLEANENV[@]}" tmux -L fm-lab new-session -d -s firstmate -n fm-leaktask \
  "exec bash --norc -c 'sleep 600'" || { log "crew window create failed"; exit 1; }

if [ "$MODE" = probe ]; then
  "${CLEANENV[@]}" tmux -L fm-lab new-session -d -s primary -c "$WT" -x 120 -y 40 \
    "${EFLAGS[@]}" bash || { log "probe session launch failed"; exit 1; }
  pane() { "${CLEANENV[@]}" tmux -L fm-lab capture-pane -p -t primary; }
  sleep 2
  "${CLEANENV[@]}" tmux -L fm-lab send-keys -t primary 'echo "probe session shell: tmux socket $TMUX"' Enter
  "${CLEANENV[@]}" tmux -L fm-lab send-keys -t primary 'echo "worktree $(pwd) @ $(git rev-parse --short HEAD); FM_HOME=$FM_HOME"' Enter
  [ "$N" != 3 ] && "${CLEANENV[@]}" tmux -L fm-lab send-keys -t primary \
    'echo "parent env: FM_CREW_STATE_META_OVERRIDE=${FM_CREW_STATE_META_OVERRIDE:-<unset>} FM_CREW_STATE_STATUS_OVERRIDE=${FM_CREW_STATE_STATUS_OVERRIDE:-<unset>}"' Enter
  "${CLEANENV[@]}" tmux -L fm-lab send-keys -t primary "bash $EF/driver.sh" Enter
  log "driver dispatched inside the lab session shell"
  t=0; DONE=0
  while [ $t -lt 180 ]; do
    if [ -f "$EF/s$N-out.txt" ] && grep -q "SCENARIO${N}_DONE" "$EF/s$N-out.txt" 2>/dev/null; then DONE=1; break; fi
    sleep 2; t=$((t+2))
  done
  sleep 2
  "${CLEANENV[@]}" tmux -L fm-lab capture-pane -p -S - -t primary > "$EF/pane-transcript.txt"
  if [ $DONE = 1 ]; then log "SCENARIO${N}_DONE observed"; else log "TIMEOUT (no SCENARIO${N}_DONE)"; fi
  Cleanup; trap - EXIT
  exit 0
fi

# --- claude primary: the real product session -------------------------------
"${CLEANENV[@]}" tmux -L fm-lab new-session -d -s primary -c "$WT" -x 120 -y 40 \
  "${EFLAGS[@]}" claude || { log "primary launch failed"; exit 1; }
log "claude primary launched on the lab socket with scenario $N parent env"

pane() { "${CLEANENV[@]}" tmux -L fm-lab capture-pane -p -t primary; }

t=0
until pane | grep -qE 'Accessing workspace|auto mode on|Message Claude|❯|»'; do
  sleep 2; t=$((t+2)); [ $t -ge 120 ] && { log "claude never booted"; pane; exit 1; }
done
log "claude rendering at ${t}s"

if pane | grep -q "Accessing workspace"; then
  "${CLEANENV[@]}" tmux -L fm-lab send-keys -t primary Down
  sleep 1
  "${CLEANENV[@]}" tmux -L fm-lab send-keys -t primary Enter
  log "trust dialog approved (Down, Enter)"
fi
t=0
until pane | grep -qE 'auto mode on|Message Claude|❯|»'; do
  sleep 2; t=$((t+2)); [ $t -ge 60 ] && { log "no input box after trust"; pane; exit 1; }
done
log "input box ready at +${t}s"

"${CLEANENV[@]}" tmux -L fm-lab send-keys -t primary \
  "Use your Bash tool to run exactly this one command, then stop and report its exit code. Do not read, modify, or create any other file: bash $EF/driver.sh"
sleep 1
"${CLEANENV[@]}" tmux -L fm-lab send-keys -t primary Enter
log "prompt sent; waiting for SCENARIO${N}_DONE"

t=0; DONE=0
while [ $t -lt 420 ]; do
  if [ -f "$EF/s$N-out.txt" ] && grep -q "SCENARIO${N}_DONE" "$EF/s$N-out.txt" 2>/dev/null; then DONE=1; break; fi
  if pane | grep -q "SCENARIO${N}_DONE"; then DONE=1; break; fi
  # A Bash permission dialog would park the run; accept the tool call.
  if pane | grep -qE 'Allow once|Allow always|Yes, allow|Yes, and stop asking'; then
    "${CLEANENV[@]}" tmux -L fm-lab send-keys -t primary Enter
    log "accepted a Bash permission dialog at +${t}s"
    sleep 2
  fi
  sleep 3; t=$((t+3))
done
"${CLEANENV[@]}" tmux -L fm-lab capture-pane -p -S - -t primary > "$EF/pane-full.txt"
sleep 3
"${CLEANENV[@]}" tmux -L fm-lab capture-pane -p -S - -t primary > "$EF/pane-at-end.txt"
if [ $DONE = 1 ]; then log "SCENARIO${N}_DONE observed in the primary"; else log "TIMEOUT (no SCENARIO${N}_DONE in pane)"; fi
# Let the primary finish its tool call and print its own report, then capture.
t=0
until pane 2>/dev/null | grep -qE 'EXIT_CODE=0|exit code 0|exited with code|Ran 1 shell command'; do
  sleep 3; t=$((t+3)); [ $t -ge 120 ] && { log "primary never printed its completion report"; break; }
done
log "primary completion report observed at +${t}s"
"${CLEANENV[@]}" tmux -L fm-lab capture-pane -p -S - -t primary > "$EF/pane-final.txt"
Cleanup; trap - EXIT
exit 0
