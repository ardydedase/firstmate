#!/usr/bin/env bash
# Live drive, phase 1d: the first launch used the home's default claude
# permission posture (bypass) and Claude Code 2.1.311 wedged the worker on the
# un-registered bypass-permissions dialog ("cursor on No, exit" - firstmate
# deliberately never answers it). Reset the task with the product's own
# teardown, switch the lab home to permission mode 'auto' (the posture
# bin/fm-live-lab.sh uses for live-launched claude workers), and re-spawn.
set -u
EV=/Users/adedase/.no-mistakes/evidence/01M5XNXTTDP4G4HP70X8E6K8M0
ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0
LOG="$EV/01d-respawn.log"
exec >"$LOG" 2>&1
PATHV=$(sed -n 's/^PATH=//p' "$EV/00-env.txt")
ID=labv1-prtail
. "$EV/lab-state.env"
le() {
  env -i HOME="$HOME" USER=adedase LOGNAME=adedase \
    PATH="$PATHV" SHELL=/bin/zsh TERM=xterm-256color LANG=en_US.UTF-8 \
    TMUX_TMPDIR="$LAB/tmux" TREEHOUSE_ROOT="$LAB/treehouse" FM_BACKEND=tmux \
    DISABLE_AUTOUPDATER=1 "$@"
}
cd "$ROOT" || exit 1

echo "### teardown the wedged task (product's own path, backend-native close)"
le env FM_HOME="$LAB" "$ROOT/bin/fm-teardown.sh" "$ID" --force
echo "teardown rc=$?"
echo "state after teardown:"; ls "$LAB/state/" | head -20

echo "### switch lab home to the supported live claude posture"
printf 'auto\n' > "$LAB/config/claude-permission-mode"

echo "### re-provision brief + backlog row if teardown removed them"
if [ ! -f "$LAB/data/$ID/brief.md" ]; then
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
fi
le env FM_HOME="$LAB" "$ROOT/bin/fm-tasks-axi.sh" add "$ID" "Live parked worker (PR-tail relaunch scenario)" --kind ship --repo notes || exit 1

echo "### re-arm trace-context session state (teardown clears state fixtures)"
SRVPID=$(le tmux display-message -p -t firstmate '#{pid}')
printf '%s\n' "$SRVPID" > "$LAB/state/.lock"
printf '%s on\n' "$SRVPID" > "$LAB/state/.trace-context-effective"

echo "### re-spawn"
T0=$(date +%s)
le env FM_HOME="$LAB" "$ROOT/bin/fm-spawn.sh" "$ID" "$LAB/projects/notes" \
  --mode local-only --yolo on --harness claude --model sonnet --effort low
RC=$?
T1=$(date +%s)
echo "spawn rc=$RC elapsed=$((T1-T0))s"
[ "$RC" -eq 0 ] || exit 1
cat "$LAB/state/$ID.meta"
le tmux list-windows -t firstmate -F '#{window_name} #{pane_current_command}'
echo "### OK phase 1d complete"
