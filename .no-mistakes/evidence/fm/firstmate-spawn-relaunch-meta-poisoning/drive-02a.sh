#!/usr/bin/env bash
# Live drive, phase 2a: spawn a SECOND real claude worker (labv1-heal), let it
# park, then damage its armed record the way the BASE revision's captain-hold
# did: plain EOF append of decisions_reviewed=/decision_keys= AFTER the PR tail
# (git show 7da4c36:bin/fm-captain-hold.sh line 1936). The product parser must
# reject the damaged record before the relaunch.
set -u
EV=/Users/adedase/.no-mistakes/evidence/01M5XNXTTDP4G4HP70X8E6K8M0
ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0
LOG="$EV/02a-spawn-poison.log"
exec >"$LOG" 2>&1
PATHV=$(sed -n 's/^PATH=//p' "$EV/00-env.txt")
ID=labv1-heal
. "$EV/lab-state.env"
le() {
  env -i HOME="$HOME" USER=adedase LOGNAME=adedase \
    PATH="$PATHV" SHELL=/bin/zsh TERM=xterm-256color LANG=en_US.UTF-8 \
    TMUX_TMPDIR="$LAB/tmux" TREEHOUSE_ROOT="$LAB/treehouse" FM_BACKEND=tmux \
    DISABLE_AUTOUPDATER=1 "$@"
}
cd "$ROOT" || exit 1

echo "### brief + backlog for $ID"
le env FM_HOME="$LAB" "$ROOT/bin/fm-brief.sh" "$ID" notes --mode local-only || exit 1
python3 - "$LAB/data/$ID/brief.md" "$LAB/state/.gate-$ID" <<'PY'
import sys
path, gate = sys.argv[1], sys.argv[2]
with open(path) as fh:
    brief = fh.read()
task = ("Lab parked worker for a live relaunch check. Add nothing yet: first "
        "park as instructed below.")
spec = ("Right after setup, append one paused status line naming the gate file "
        + gate + " and end your turn. Do not poll or sleep in a foreground "
        "command. When a later message resumes you, check that " + gate +
        " exists before doing anything; if it is absent, remain paused and "
        "end your turn again. Nothing else is in scope.")
with open(path, "w") as fh:
    fh.write(brief.replace("{TASK}", task).replace("{FIRSTMATE_SPEC}", spec))
PY
le env FM_HOME="$LAB" "$ROOT/bin/fm-tasks-axi.sh" add "$ID" "Live parked worker (poisoned-input heal scenario)" --kind ship --repo notes || exit 1

echo "### spawn"
T0=$(date +%s)
le env FM_HOME="$LAB" "$ROOT/bin/fm-spawn.sh" "$ID" "$LAB/projects/notes" \
  --mode local-only --yolo on --harness claude --model sonnet --effort low
RC=$?
T1=$(date +%s)
echo "spawn rc=$RC elapsed=$((T1-T0))s"
[ "$RC" -eq 0 ] || exit 1

echo "### wait for the worker's first parked turn"
T0=$(date +%s)
while [ ! -e "$LAB/state/$ID.turn-ended" ]; do
  T=$(date +%s); [ $((T-T0)) -lt 360 ] || { echo "TIMEOUT waiting for turn-ended"; break; }
  sleep 3
done
T1=$(date +%s)
echo "turn-ended after $((T1-T0))s"
cat "$LAB/state/$ID.status" 2>/dev/null || echo "(no status)"
le tmux capture-pane -p -t firstmate:fm-$ID > "$EV/02-pane-before.txt"
le tmux list-windows -t firstmate -F '#{window_name} #{pane_current_command}'

echo "### arm the PR tail, then poison it the way base captain-hold did"
META="$LAB/state/$ID.meta"
{
  printf 'pr=https://github.com/example/repo/pull/1913\n'
  printf 'pr_head=%s\n' '7d1e5f0c9b8a7d6e5f4c3b2a1908d7c6b5a4938'
  printf 'x_request=%s\n' 'labv1-heal-relay-91bc'
  printf 'x_request_ts=1793072400\n'
  printf 'x_followups=0\n'
  printf 'x_platform=x\n'
  printf 'decisions_reviewed=1\n'
  printf 'decision_keys=labv1-heal:1:origin/notes\n'
} >> "$META"
cp "$META" "$EV/02-meta-poisoned.txt"
stat -f 'mode=%Sp' "$META"
echo "### product parser on the DAMAGED record (pre-relaunch) - expect FAIL"
"$EV/check-meta.sh" "$META" "$LAB/state" "PRE-RELAUNCH poisoned record (target)" | tee "$EV/02-check-poisoned.txt"
echo "### OK phase 2a complete"
