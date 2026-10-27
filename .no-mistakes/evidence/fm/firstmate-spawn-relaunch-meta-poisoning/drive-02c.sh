#!/usr/bin/env bash
# Live drive, phase 2c: complete scenario 2 cleanly.
#  (1) Repair MY fixture error from 2b: the seeded pr_head was 39 hex chars
#      (one short of the required 40); the relaunch preserved it verbatim, as
#      designed. With a valid pr_head the healed record from 2b must parse.
#  (2) Re-poison the record exactly as base captain-hold did (EOF append of
#      decisions rows after the tail) with the VALID fixture, verify the
#      product parser rejects it.
#  (3) Relaunch again and verify the heal end to end: decisions rows before
#      the tail, tail last, parser PASS, replacement agent parks.
set -u
EV=/Users/adedase/.no-mistakes/evidence/01M5XNXTTDP4G4HP70X8E6K8M0
ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0
LOG="$EV/02c-heal-clean.log"
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
HEAD40=7d1e5f0c9b8a7d6e5f4c3b2a1908d7c6b5a49381   # 40 hex chars
[ "${#HEAD40}" -eq 40 ] || { echo "fixture bug: bad HEAD40"; exit 1; }

echo "### (1) repair the fixture pr_head row on the live record (39 -> 40 hex)"
python3 - "$META" "$HEAD40" <<'PY'
import sys
path, head = sys.argv[1], sys.argv[2]
with open(path) as fh:
    rows = fh.read().splitlines(True)
fixed = 0
out = []
for r in rows:
    if r.startswith("pr_head="):
        r = "pr_head=" + head + ("\n" if r.endswith("\n") else "")
        fixed += 1
    out.append(r)
with open(path, "w") as fh:
    fh.write("".join(out))
print(f"pr_head rows repaired: {fixed}")
PY
"$EV/check-meta.sh" "$META" "$LAB/state" "2b record after fixture repair (healed order + valid pr_head)" | tee "$EV/02-check-repaired.txt"

echo "### (2) re-poison exactly as base captain-hold did (EOF append after tail)"
cp "$META" "$EV/02-meta-armed.txt"
printf 'decisions_reviewed=1\ndecision_keys=%s\n' "labv1-heal:2:origin/notes" >> "$META"
cp "$META" "$EV/02-meta-poisoned.txt"
"$EV/check-meta.sh" "$META" "$LAB/state" "PRE-RELAUNCH poisoned record (target, valid fixture)" | tee "$EV/02-check-poisoned.txt"

echo "### (3) relaunch (live)"
T0=$(date +%s)
le env FM_HOME="$LAB" "$ROOT/bin/fm-control.sh" "$ID" relaunch \
  --note "live check: keep parking until the gate file exists"
RC=$?
T1=$(date +%s)
echo "relaunch rc=$RC elapsed=$((T1-T0))s"
[ "$RC" -eq 0 ] || { echo "RELAUNCH FAILED"; exit 1; }

echo "### replacement record, verbatim"
cat "$META" > "$EV/02-meta-after.txt"
cat "$META"
stat -f 'mode=%Sp' "$META"
echo "### product parser + ordering facts (expect HEAL: PASS)"
"$EV/check-meta.sh" "$META" "$LAB/state" "POST-RELAUNCH healed record (target, valid fixture)" | tee "$EV/02-check-after.txt"

echo "### wait for the replacement agent's parked turn"
T0=$(date +%s)
while [ "$(grep -c '^paused' "$LAB/state/$ID.status" 2>/dev/null || echo 0)" -lt 3 ]; do
  T=$(date +%s); [ $((T-T0)) -lt 300 ] || { echo "TIMEOUT waiting for replacement park"; break; }
  sleep 3
done
T1=$(date +%s)
echo "replacement parked after $((T1-T0))s"
cat "$LAB/state/$ID.status"
le tmux capture-pane -p -t firstmate:fm-$ID > "$EV/02-pane-final.txt"
le tmux list-windows -t firstmate -F '#{window_name} #{pane_current_command}'
echo "### OK phase 2c complete"
