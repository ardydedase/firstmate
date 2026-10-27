#!/usr/bin/env bash
# Live drive, phase 1a: mint the lab home, private tmux server, notes project,
# task brief + backlog row, and spawn a REAL claude ship worker from this gate
# worktree. Everything real: claude CLI, treehouse lease, tmux pane, task record.
set -u
EV=/Users/adedase/.no-mistakes/evidence/01M5XNXTTDP4G4HP70X8E6K8M0
ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0
LOG="$EV/01a-setup-spawn.log"
exec >"$LOG" 2>&1

PATHV=$(sed -n 's/^PATH=//p' "$EV/00-env.txt")
ID=labv1-prtail

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX") || { echo "FATAL: mktemp"; exit 1; }
printf 'LAB=%s\n' "$LAB" > "$EV/lab-state.env"

le() {  # clean lab environment (mirrors bin/fm-live-lab.sh's lab_env_base)
  env -i HOME="$HOME" USER=adedase LOGNAME=adedase \
    PATH="$PATHV" SHELL=/bin/zsh TERM=xterm-256color LANG=en_US.UTF-8 \
    TMUX_TMPDIR="$LAB/tmux" TREEHOUSE_ROOT="$LAB/treehouse" FM_BACKEND=tmux \
    DISABLE_AUTOUPDATER=1 "$@"
}

echo "### lab home: $LAB"
cd "$ROOT" || exit 1

"$ROOT/bin/fm-lab-home.sh" create "$LAB" || { echo "FATAL: lab-home create"; exit 1; }
mkdir -p "$LAB/tmux" "$LAB/treehouse" "$LAB/projects"
printf 'tmux\n' > "$LAB/config/backend"
touch "$LAB/config/trace-context"   # end-user opt-in: this home records traceparent=
echo "marker: $(cat "$LAB/.fm-lab-home" 2>/dev/null)"

echo "### private tmux server (default socket name under lab-private TMUX_TMPDIR)"
le tmux -f /dev/null new-session -d -s firstmate -n lab -x 220 -y 60 -c "$ROOT" || { echo "FATAL: tmux server"; exit 1; }
SRVPID=$(le tmux display-message -p -t firstmate '#{pid}')
echo "tmux server pid: $SRVPID"
le tmux list-sessions

echo "### notes project (seed -> bare origin -> clone), registry row"
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

echo "### brief + backlog row for $ID"
le env FM_HOME="$LAB" "$ROOT/bin/fm-brief.sh" "$ID" notes --mode local-only || { echo "FATAL: brief"; exit 1; }
BRIEF="$LAB/data/$ID/brief.md"
python3 - "$BRIEF" "$LAB/state/.gate-$ID" <<'PY' || { echo "FATAL: brief fill"; exit 1; }
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
brief = brief.replace("{TASK}", task).replace("{FIRSTMATE_SPEC}", spec)
with open(path, "w") as fh:
    fh.write(brief)
PY
grep -n "gate file" "$BRIEF" | head -2

le env FM_HOME="$LAB" "$ROOT/bin/fm-tasks-axi.sh" add "$ID" "Live parked worker (PR-tail relaunch scenario)" --kind ship --repo notes || { echo "FATAL: backlog add"; exit 1; }

echo "### session trace-context state (models a primary session with trace-context on)"
printf '%s\n' "$SRVPID" > "$LAB/state/.lock"
printf '%s on\n' "$SRVPID" > "$LAB/state/.trace-context-effective"

echo "### spawn (real claude ship worker, launched into the lab tmux)"
T0=$(date +%s)
le env FM_HOME="$LAB" "$ROOT/bin/fm-spawn.sh" "$ID" "$LAB/projects/notes" \
  --mode local-only --yolo on --harness claude --model sonnet --effort low
RC=$?
T1=$(date +%s)
echo "spawn rc=$RC elapsed=$((T1-T0))s"
[ "$RC" -eq 0 ] || exit 1

echo "### task record as the spawn wrote it"
cat "$LAB/state/$ID.meta"
stat -f 'meta mode=%Sp' "$LAB/state/$ID.meta"
ls -la "$LAB/state/" | head -20
echo "windows:"
le tmux list-windows -t firstmate -F '#{window_index} #{window_name} #{pane_current_command}'
echo "### OK phase 1a complete"
