#!/usr/bin/env bash
# Live drive, phase 1b: re-run the spawn with FM_HOME at its PHYSICAL path
# (macOS /var -> /private/var): fm_gate_lab_permitted requires
# FM_HOME == (cd FM_HOME && pwd -P).
set -u
EV=/Users/adedase/.no-mistakes/evidence/01M5XNXTTDP4G4HP70X8E6K8M0
ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0
LOG="$EV/01b-spawn.log"
exec >"$LOG" 2>&1
PATHV=$(sed -n 's/^PATH=//p' "$EV/00-env.txt")
ID=labv1-prtail
. "$EV/lab-state.env"
LAB=$(cd "$LAB" && pwd -P)
printf 'LAB=%s\n' "$LAB" > "$EV/lab-state.env"
echo "### LAB physical: $LAB"

le() {
  env -i HOME="$HOME" USER=adedase LOGNAME=adedase \
    PATH="$PATHV" SHELL=/bin/zsh TERM=xterm-256color LANG=en_US.UTF-8 \
    TMUX_TMPDIR="$LAB/tmux" TREEHOUSE_ROOT="$LAB/treehouse" FM_BACKEND=tmux \
    DISABLE_AUTOUPDATER=1 "$@"
}
cd "$ROOT" || exit 1
echo "### gate state: marker present, FM_HOME physical"
ls -la "$LAB/.fm-lab-home"

echo "### spawn (real claude ship worker into lab tmux)"
T0=$(date +%s)
le env FM_HOME="$LAB" "$ROOT/bin/fm-spawn.sh" "$ID" "$LAB/projects/notes" \
  --mode local-only --yolo on --harness claude --model sonnet --effort low
RC=$?
T1=$(date +%s)
echo "spawn rc=$RC elapsed=$((T1-T0))s"
[ "$RC" -eq 0 ] || exit 1

echo "### task record as the spawn wrote it"
cat "$LAB/state/$ID.meta"
stat -f 'meta mode=%Sp size=%z' "$LAB/state/$ID.meta"
echo "windows:"
le tmux list-windows -t firstmate -F '#{window_index} #{window_name} #{pane_current_command}'
echo "### OK phase 1b complete"
