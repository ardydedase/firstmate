#!/usr/bin/env bash
# Live drive, phase 3b: complete the BASE contrast cleanly. The 3a seeded
# pr_head was 39 hex chars (fixture bug, mine: the relaunch preserved it
# verbatim as designed, so the parser failure had two causes). Repair the
# row to a verified 40-hex value, verify the armed record PARSES at base,
# then relaunch at base and verify the parser REJECTS the replacement record
# for the one reason this change fixes: control_relaunch_tx=/traceparent=
# appended AFTER the preserved pr=/pr_head=/x_* tail.
set -u
EV=/Users/adedase/.no-mistakes/evidence/01M5XNXTTDP4G4HP70X8E6K8M0
ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0
BASE=7da4c3621370534ff9689843d2b77f34158057fb
TARGET=7945109a64772cdd4b790a8cf6a6653c2ee2d801
LOG="$EV/03b-base-contrast.log"
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
META="$LAB/state/$ID.meta"
HEAD40=5c2b8e1f4a7d9b6c3e8f0a2d1b4c5e6f7a8b9c0d
[ "${#HEAD40}" -eq 40 ] || { echo "fixture bug: HEAD40 len ${#HEAD40}"; exit 1; }

echo "### checkout BASE"
git checkout -q "$BASE" || { echo "FATAL checkout base"; exit 1; }
git rev-parse HEAD

echo "### repair the fixture pr_head row (39 -> 40 hex), then verify parse"
python3 - "$META" "$HEAD40" <<'PY'
import sys
path, head = sys.argv[1], sys.argv[2]
with open(path) as fh:
    rows = fh.read().splitlines(True)
out = []
fixed = 0
for r in rows:
    if r.startswith("pr_head="):
        r = "pr_head=" + head + ("\n" if r.endswith("\n") else "")
        fixed += 1
    out.append(r)
with open(path, "w") as fh:
    fh.write("".join(out))
print(f"pr_head rows repaired: {fixed}")
PY
cp "$META" "$EV/03-meta-armed.txt"
"$EV/check-meta.sh" "$META" "$LAB/state" "PRE-RELAUNCH armed record (BASE, valid fixture)" | tee "$EV/03-check-armed.txt"

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
echo "### product parser on the BASE replacement record - expect FAIL on row order"
"$EV/check-meta.sh" "$META" "$LAB/state" "POST-RELAUNCH record (BASE, valid fixture)" | tee "$EV/03-check-after.txt"

echo "### restore TARGET"
git checkout -q "$TARGET" || { echo "FATAL: could not restore target"; exit 1; }
git rev-parse HEAD
git status --porcelain | head -3
echo "### OK phase 3b complete"
