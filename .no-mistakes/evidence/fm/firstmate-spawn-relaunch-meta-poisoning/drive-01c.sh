#!/usr/bin/env bash
# Live drive, phase 1c: wait for the real worker's first parked turn, capture
# the pane, then seed the PR identity tail (the state an armed + x-linked task
# record carries) and verify the product parser accepts it pre-relaunch.
set -u
EV=/Users/adedase/.no-mistakes/evidence/01M5XNXTTDP4G4HP70X8E6K8M0
ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0
LOG="$EV/01c-arm.log"
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

echo "### waiting for the worker's first turn to end (turn-ended marker)"
T0=$(date +%s)
while [ ! -e "$LAB/state/$ID.turn-ended" ]; do
  T=$(date +%s); [ $((T-T0)) -lt 300 ] || { echo "TIMEOUT waiting for turn-ended"; break; }
  sleep 3
done
T1=$(date +%s)
echo "turn-ended after $((T1-T0))s: $(ls -la "$LAB/state/$ID.turn-ended" 2>/dev/null || echo MISSING)"

echo "### status file (the worker's posted status lines)"
cat "$LAB/state/$ID.status" 2>/dev/null || echo "(no status file)"

echo "### pane capture BEFORE relaunch (the real claude worker, parked)"
le tmux capture-pane -p -t firstmate:fm-labv1-prtail > "$EV/01-pane-before.txt"
sed -n '1,12p' "$EV/01-pane-before.txt"
echo "...(full capture: 01-pane-before.txt)"
le tmux list-windows -t firstmate -F '#{window_name} #{pane_current_command}'

echo "### seed the armed+x-linked tail (what fm-pr-check/fm-x-lib leave behind)"
META="$LAB/state/$ID.meta"
cp "$META" "$EV/01-meta-before-seed.txt"
{
  printf 'pr=https://github.com/example/repo/pull/1912\n'
  printf 'pr_head=%s\n' '3f9c2a77b5e1d0a6c8b4e5f2a1b0c9d8e7f6a5b4'
  printf 'x_request=%s\n' 'labv1-prtail-relay-4f2a'
  printf 'x_request_ts=1793072400\n'
  printf 'x_followups=0\n'
  printf 'x_platform=x\n'
} >> "$META"
cp "$META" "$EV/01-meta-armed.txt"
stat -f 'armed meta mode=%Sp' "$META"

echo "### product parser on the armed record (pre-relaunch)"
"$EV/check-meta.sh" "$META" "$LAB/state" "PRE-RELAUNCH armed record (target)" | tee "$EV/01-check-armed.txt"
echo "### OK phase 1c complete"
