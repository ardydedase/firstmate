#!/usr/bin/env bash
# Live drive, phase 1f: THE SCENARIO. Operator runs
#   bin/fm-control.sh <id> relaunch --note <...>
# against the live PR-armed parked claude worker, from the gate worktree, with
# the marked lab home. Then check the replacement record with firstmate's own
# identity parser and ordering facts.
set -u
EV=/Users/adedase/.no-mistakes/evidence/01M5XNXTTDP4G4HP70X8E6K8M0
ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0
LOG="$EV/01f-relaunch.log"
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
META="$LAB/state/$ID.meta"
cp "$META" "$EV/01-meta-armed.txt"

echo "### relaunch (live, stop + respwan through the relaunch branch)"
T0=$(date +%s)
le env FM_HOME="$LAB" "$ROOT/bin/fm-control.sh" "$ID" relaunch \
  --note "live check: keep parking until the gate file exists"
RC=$?
T1=$(date +%s)
echo "relaunch rc=$RC elapsed=$((T1-T0))s"
[ "$RC" -eq 0 ] || { echo "RELAUNCH FAILED"; }

echo "### replacement record, verbatim"
cat "$META" > "$EV/01-meta-after.txt"
cat "$META"
stat -f 'mode=%Sp' "$META"

echo "### product parser + ordering facts on the live replacement record"
"$EV/check-meta.sh" "$META" "$LAB/state" "POST-RELAUNCH record (target)" | tee "$EV/01-check-after.txt"

echo "### pane capture right after relaunch"
le tmux capture-pane -p -t firstmate:fm-$ID > "$EV/01-pane-after.txt"
le tmux list-windows -t firstmate -F '#{window_name} #{pane_current_command}'

echo "### wait for the replacement agent's parked turn (new paused status line)"
T0=$(date +%s)
while ! tail -5 "$LAB/state/$ID.status" 2>/dev/null | grep -q "1793073034"; do :; done 2>/dev/null || true
# (the first park was at=1793073034; wait until a second paused line appears)
T0=$(date +%s)
while [ "$(grep -c '^paused' "$LAB/state/$ID.status" 2>/dev/null || echo 0)" -lt 2 ]; do
  T=$(date +%s); [ $((T-T0)) -lt 300 ] || { echo "TIMEOUT waiting for replacement park"; break; }
  sleep 3
done
T1=$(date +%s)
echo "replacement parked after $((T1-T0))s"
echo "### status file:"; cat "$LAB/state/$ID.status"
echo "### final pane capture:"
le tmux capture-pane -p -t firstmate:fm-$ID > "$EV/01-pane-final.txt"
wc -l "$EV/01-pane-final.txt"
echo "### OK phase 1f complete"
