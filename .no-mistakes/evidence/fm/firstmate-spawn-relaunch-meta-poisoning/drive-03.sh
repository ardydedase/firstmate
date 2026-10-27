#!/usr/bin/env bash
# Live drive, phase 3: BASE-REVISION CONTRAST (fail-before-fix). Check the
# worktree out at the base commit 7da4c362, spawn a real worker from the BASE
# scripts, arm the same PR tail, verify it parses, then run the BASE
# fm-control relaunch. Expectation: the relaunch succeeds but appends
# control_relaunch_tx= AFTER the preserved pr=/pr_head=/x_* tail, and the
# product parser then rejects the live record - the exact defect this change
# fixes. Afterwards restore the worktree to the target commit.
set -u
EV=/Users/adedase/.no-mistakes/evidence/01M5XNXTTDP4G4HP70X8E6K8M0
ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0
BASE=7da4c3621370534ff9689843d2b77f34158057fb
TARGET=7945109a64772cdd4b790a8cf6a6653c2ee2d801
LOG="$EV/03-base-contrast.log"
exec >"$LOG" 2>&1
PATHV=$(sed -n 's/^PATH=//p' "$EV/00-env.txt")
ID=labv1-base
. "$EV/lab-state.env"
le() {
  env -i HOME="$HOME" USER=adedase LOGNAME=adedase \
    PATH="$PATHV" SHELL=/bin/zsh TERM=xterm-256color LANG=en_US.UTF-8 \
    TMUX_TMPDIR="$LAB/tmux" TREEHOUSE_ROOT="$LAB/treehouse" FM_BACKEND=tmux \
    DISABLE_AUTOUPDATER=1 "$@"
}
cd "$ROOT" || exit 1

echo "### worktree state before checkout"
git rev-parse HEAD; git status --porcelain | head -3
echo "### checkout BASE $BASE"
git checkout -q "$BASE" || { echo "FATAL checkout base"; exit 1; }
git rev-parse HEAD

echo "### brief + backlog (BASE scripts)"
le env FM_HOME="$LAB" "$ROOT/bin/fm-brief.sh" "$ID" notes --mode local-only || { git checkout -q "$TARGET"; exit 1; }
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
le env FM_HOME="$LAB" "$ROOT/bin/fm-tasks-axi.sh" add "$ID" "Live parked worker (base contrast scenario)" --kind ship --repo notes || { git checkout -q "$TARGET"; exit 1; }

echo "### spawn from BASE scripts"
T0=$(date +%s)
le env FM_HOME="$LAB" "$ROOT/bin/fm-spawn.sh" "$ID" "$LAB/projects/notes" \
  --mode local-only --yolo on --harness claude --model sonnet --effort low
RC=$?
T1=$(date +%s)
echo "spawn rc=$RC elapsed=$((T1-T0))s"
[ "$RC" -eq 0 ] || { git checkout -q "$TARGET"; exit 1; }

echo "### wait for the worker's first parked turn"
T0=$(date +%s)
while [ ! -e "$LAB/state/$ID.turn-ended" ]; do
  T=$(date +%s); [ $((T-T0)) -lt 360 ] || { echo "TIMEOUT waiting for turn-ended"; break; }
  sleep 3
done
T1=$(date +%s)
echo "turn-ended after $((T1-T0))s"
cat "$LAB/state/$ID.status" 2>/dev/null || echo "(no status)"
le tmux capture-pane -p -t firstmate:fm-$ID > "$EV/03-pane-before.txt"
le tmux list-windows -t firstmate -F '#{window_name} #{pane_current_command}'

echo "### arm the same healthy PR tail"
META="$LAB/state/$ID.meta"
{
  printf 'pr=https://github.com/example/repo/pull/1914\n'
  printf 'pr_head=%s\n' '5c2b8e1f4a7d9b6c3e8f0a2d1b4c5e6f7a8b9c0'
  printf 'x_request=%s\n' 'labv1-base-relay-77ad'
  printf 'x_request_ts=1793072400\n'
  printf 'x_followups=0\n'
  printf 'x_platform=x\n'
} >> "$META"
cp "$META" "$EV/03-meta-armed.txt"
"$EV/check-meta.sh" "$META" "$LAB/state" "PRE-RELAUNCH armed record (BASE)" | tee "$EV/03-check-armed.txt"

echo "### relaunch on BASE (live)"
T0=$(date +%s)
le env FM_HOME="$LAB" "$ROOT/bin/fm-control.sh" "$ID" relaunch \
  --note "live check: keep parking until the gate file exists"
RC=$?
T1=$(date +%s)
echo "relaunch rc=$RC elapsed=$((T1-T0))s"
[ "$RC" -eq 0 ] || echo "NOTE: base relaunch rc=$RC"

echo "### replacement record at BASE, verbatim"
cat "$META" > "$EV/03-meta-after.txt"
cat "$META"
stat -f 'mode=%Sp' "$META"
echo "### product parser on the BASE replacement record - expect FAIL (the defect)"
"$EV/check-meta.sh" "$META" "$LAB/state" "POST-RELAUNCH record (BASE)" | tee "$EV/03-check-after.txt"

echo "### restore the worktree to TARGET"
git checkout -q "$TARGET" || { echo "FATAL: could not restore target checkout"; exit 1; }
git rev-parse HEAD
git status --porcelain | head -3
echo "### OK phase 3 complete"
