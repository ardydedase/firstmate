#!/usr/bin/env bash
# Live drive, phase 2b: relaunch the task whose record was poisoned after the
# tail (base captain-hold shape). Expectation at the target revision: the
# relaunch's record rewrite defers the pr=/pr_head=/x_* tail to the end, slots
# the legacy decisions rows before it, and the product parser accepts the
# replacement record again (the heal). The replacement agent must actually
# run and park.
set -u
EV=/Users/adedase/.no-mistakes/evidence/01M5XNXTTDP4G4HP70X8E6K8M0
ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0
LOG="$EV/02b-relaunch.log"
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
META="$LAB/state/$ID.meta"

echo "### relaunch the poisoned task (live)"
T0=$(date +%s)
le env FM_HOME="$LAB" "$ROOT/bin/fm-control.sh" "$ID" relaunch \
  --note "live check: keep parking until the gate file exists"
RC=$?
T1=$(date +%s)
echo "relaunch rc=$RC elapsed=$((T1-T0))s"
[ "$RC" -eq 0 ] || echo "RELAUNCH FAILED rc=$RC"

echo "### replacement record, verbatim"
cat "$META" > "$EV/02-meta-after.txt"
cat "$META"
stat -f 'mode=%Sp' "$META"

echo "### product parser + ordering facts (expect HEAL: PASS)"
"$EV/check-meta.sh" "$META" "$LAB/state" "POST-RELAUNCH healed record (target)" | tee "$EV/02-check-after.txt"

echo "### wait for the replacement agent's parked turn"
T0=$(date +%s)
while [ "$(grep -c '^paused' "$LAB/state/$ID.status" 2>/dev/null || echo 0)" -lt 2 ]; do
  T=$(date +%s); [ $((T-T0)) -lt 300 ] || { echo "TIMEOUT waiting for replacement park"; break; }
  sleep 3
done
T1=$(date +%s)
echo "replacement parked after $((T1-T0))s"
cat "$LAB/state/$ID.status"
le tmux capture-pane -p -t firstmate:fm-$ID > "$EV/02-pane-final.txt"
le tmux list-windows -t firstmate -F '#{window_name} #{pane_current_command}'
echo "### OK phase 2b complete"
