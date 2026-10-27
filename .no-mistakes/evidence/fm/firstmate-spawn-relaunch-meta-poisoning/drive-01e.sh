#!/usr/bin/env bash
# Live drive, phase 1e: full lab reset. The first lab minted TREEHOUSE_ROOT and
# the tmux server env on the unresolved /var/folders path while FM_HOME had to
# be the physical /private/var path (fm_gate_lab_permitted requires it), and a
# teardown then could not return the treehouse lease across the mismatch. Re-mint
# the lab with ONE canonical physical path everywhere, spawn the parked worker
# with the supported live posture (claude permission mode auto), wait for its
# first parked turn, capture the pane, then arm the PR tail and check the
# product parser.
set -u
EV=/Users/adedase/.no-mistakes/evidence/01M5XNXTTDP4G4HP70X8E6K8M0
ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0
LOG="$EV/01e-fresh-spawn.log"
exec >"$LOG" 2>&1
PATHV=$(sed -n 's/^PATH=//p' "$EV/00-env.txt")
ID=labv1-prtail
. "$EV/lab-state.env" 2>/dev/null || LAB=

echo "### kill the old lab's private tmux server and remove the old lab"
if [ -n "${LAB:-}" ]; then
  env -i HOME="$HOME" PATH="$PATHV" TERM=xterm-256color TMUX_TMPDIR="$LAB/tmux" tmux kill-server 2>/dev/null
  rm -rf "$LAB"
  rm -rf "/tmp/fm-$ID" "/tmp/fm-$ID"gotmp
fi

RAW=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX") || exit 1
LAB=$(cd "$RAW" && pwd -P)          # physical path, the one form used everywhere
printf 'LAB=%s\n' "$LAB" > "$EV/lab-state.env"
echo "### fresh lab (physical): $LAB"

le() {
  env -i HOME="$HOME" USER=adedase LOGNAME=adedase \
    PATH="$PATHV" SHELL=/bin/zsh TERM=xterm-256color LANG=en_US.UTF-8 \
    TMUX_TMPDIR="$LAB/tmux" TREEHOUSE_ROOT="$LAB/treehouse" FM_BACKEND=tmux \
    DISABLE_AUTOUPDATER=1 "$@"
}
cd "$ROOT" || exit 1

"$ROOT/bin/fm-lab-home.sh" create "$LAB" || exit 1
mkdir -p "$LAB/tmux" "$LAB/treehouse" "$LAB/projects"
printf 'tmux\n' > "$LAB/config/backend"
printf 'auto\n' > "$LAB/config/claude-permission-mode"
touch "$LAB/config/trace-context"

le tmux -f /dev/null new-session -d -s firstmate -n lab -x 220 -y 60 -c "$ROOT" || exit 1
SRVPID=$(le tmux display-message -p -t firstmate '#{pid}')
printf '%s\n' "$SRVPID" > "$LAB/state/.lock"
printf '%s on\n' "$SRVPID" > "$LAB/state/.trace-context-effective"
echo "tmux server pid: $SRVPID (sessions: $(le tmux list-sessions 2>/dev/null))"

SEED="$LAB/origins/notes-seed"; ORIGIN="$LAB/origins/notes.git"
mkdir -p "$SEED/notes" "$SEED/tests"
git init -q -b main "$SEED"
cat > "$SEED/notes/__init__.py" <<'PY'
"""A tiny notes library used by the firstmate live lab."""

NOTES = []


def add_note(text, tags=None):
    NOTES.append({"text": text, "tags": list(tags or [])})
    return len(NOTES) - 1


def list_notes():
    return list(NOTES)
PY
cat > "$SEED/tests/test_notes.py" <<'PY'
import unittest

import notes


class NotesTest(unittest.TestCase):
    def setUp(self):
        notes.NOTES.clear()

    def test_add_and_list(self):
        notes.add_note("hello", ["a"])
        self.assertEqual(notes.list_notes(), [{"text": "hello", "tags": ["a"]}])


if __name__ == "__main__":
    unittest.main()
PY
cat > "$SEED/README.md" <<'MD'
# notes

A tiny notes library for lab work.
Run the checks with `python3 -m unittest discover -s tests`.
MD
git -C "$SEED" add -A
git -C "$SEED" -c user.name=lab -c user.email=lab@example.invalid commit -q -m "seed notes"
git clone -q --bare "$SEED" "$ORIGIN"
rm -rf "$SEED"
git clone -q "$ORIGIN" "$LAB/projects/notes"
printf '# Projects\n\n- notes [local-only +yolo] - tiny lab notes library\n' > "$LAB/data/projects.md"

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
le env FM_HOME="$LAB" "$ROOT/bin/fm-tasks-axi.sh" add "$ID" "Live parked worker (PR-tail relaunch scenario)" --kind ship --repo notes || exit 1

echo "### spawn (permission mode auto, trace-context on)"
T0=$(date +%s)
le env FM_HOME="$LAB" "$ROOT/bin/fm-spawn.sh" "$ID" "$LAB/projects/notes" \
  --mode local-only --yolo on --harness claude --model sonnet --effort low
RC=$?
T1=$(date +%s)
echo "spawn rc=$RC elapsed=$((T1-T0))s"
[ "$RC" -eq 0 ] || exit 1
cat "$LAB/state/$ID.meta"

echo "### waiting for the worker's first parked turn (turn-ended marker)"
T0=$(date +%s)
while [ ! -e "$LAB/state/$ID.turn-ended" ]; do
  T=$(date +%s); [ $((T-T0)) -lt 360 ] || { echo "TIMEOUT waiting for turn-ended"; break; }
  sleep 3
done
T1=$(date +%s)
echo "turn-ended after $((T1-T0))s: $(ls -la "$LAB/state/$ID.turn-ended" 2>/dev/null || echo MISSING)"
echo "### status file:"; cat "$LAB/state/$ID.status" 2>/dev/null || echo "(none)"
echo "### pane capture BEFORE relaunch:"
le tmux capture-pane -p -t firstmate:fm-$ID > "$EV/01-pane-before.txt"
le tmux list-windows -t firstmate -F '#{window_name} #{pane_current_command}'
wc -l "$EV/01-pane-before.txt"

echo "### arm the PR identity tail"
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
echo "### product parser on the armed record (pre-relaunch)"
"$EV/check-meta.sh" "$META" "$LAB/state" "PRE-RELAUNCH armed record (target)" | tee "$EV/01-check-armed.txt"
echo "### OK phase 1e complete"
