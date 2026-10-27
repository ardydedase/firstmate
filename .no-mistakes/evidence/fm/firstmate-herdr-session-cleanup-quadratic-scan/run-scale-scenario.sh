#!/usr/bin/env bash
# Live scale scenario for fm/firstmate-herdr-session-cleanup-quadratic-scan.
#
# Reproduces the reported failure shape in one isolated Herdr lab:
#   - a marked disposable FM_HOME holding 65 valid *.herdr-presentation journals
#   - a named non-default fm-lab-* Herdr session holding 34 grammar-titled
#     candidate workspaces (33 unmatched + 1 exactly-matching stale child)
#     plus one focused non-candidate anchor
# then drives, against that same fixture:
#   1. the BASE revision (46df160) full locked session start -> must truncate
#      at its 120s runtime bound during the bootstrap stage (reported failure)
#   2. the TARGET revision (efe0338) full locked session start -> must deliver
#      the complete digest inside the bound, retiring exactly the stale child
#   3. the TARGET cleanup pass alone, timed, to isolate the component cost
#
# Every Herdr CLI call goes through bin/fm-herdr-lab.sh (guarded named lab).
# The live default fleet session is only ever read (session list / tripwire).
set -u

ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XHEGXYW5HRHX43S4AW3MTN
EV=/Users/adedase/.no-mistakes/evidence/01M5XHEGXYW5HRHX43S4AW3MTN
BASE_COMMIT=46df16088f8e37321b824f87187e95ad3f670355
LAB_HELPER=$ROOT/bin/fm-herdr-lab.sh
REAL_HERDR=$(command -v herdr)
HERDR_ORIGINAL_PATH=$PATH

now() { python3 -c 'import time; print(f"{time.time():.2f}")'; }
say() { printf '\n=== %s ===\n' "$*"; }

SESSIONS_BEFORE=$(herdr session list --json 2>/dev/null)

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-scale-scenario.XXXXXX")
FAKEBIN=$TMP/fakebin
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
mkdir -p "$FAKEBIN"

cleanup() {
  local status=$?
  say "cleanup"
  if [ -n "${S:-}" ]; then
    env PATH="$HERDR_ORIGINAL_PATH" "$LAB_HELPER" teardown "$S" || status=1
  fi
  rm -rf "$LAB" "$TMP"
  printf '%s\n' "$SESSIONS_BEFORE" > "$EV/00-sessions-before.json"
  herdr session list --json 2>/dev/null > "$EV/07-sessions-after.json" || true
  if ! diff -q "$EV/00-sessions-before.json" "$EV/07-sessions-after.json" >/dev/null; then
    say "FLEET SESSION LIST CHANGED - INVESTIGATE"
    status=1
  fi
  # Kill only network workers that belong to this run's lab home.
  for pid in $(pgrep -f 'fm-startup-network|fm-inactive-reconcile' 2>/dev/null); do
    if lsof -p "$pid" 2>/dev/null | grep -qF "$LAB"; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  exit "$status"
}
trap cleanup EXIT

# --- lab session ------------------------------------------------------------
S=$("$LAB_HELPER" name cleanupscale) || exit 1
printf 'lab session: %s\n' "$S"
env PATH="$HERDR_ORIGINAL_PATH" "$LAB_HELPER" provision "$S" || exit 1
lab() { env PATH="$HERDR_ORIGINAL_PATH" "$LAB_HELPER" run "$S" "$@"; }

# --- guarded herdr transport (as in tests/fm-herdr-session-cleanup-e2e) -----
export REAL_HERDR HERDR_ORIGINAL_PATH
export HERDR_LAB_HELPER="$LAB_HELPER"
cat > "$FAKEBIN/herdr" <<'SH'
#!/usr/bin/env bash
set -u
args=("$@")
last=$((${#args[@]} - 1))
flag=$((last - 1))
if [ ${#args[@]} -ge 2 ] \
  && [ "${args[$flag]}" = --session ] \
  && [ "${args[$last]}" = "$HERDR_LAB_SESSION" ]; then
  unset "args[$last]" "args[$flag]"
fi
set -- "${args[@]}"
for arg in "$@"; do
  case "$arg" in --session|--session=*) exit 9 ;; esac
done
if [ "${1:-}" = --version ]; then
  exec env PATH="$HERDR_ORIGINAL_PATH" "$REAL_HERDR" "$@" --session "$HERDR_LAB_SESSION"
fi
exec env PATH="$HERDR_ORIGINAL_PATH" "$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" "$@"
SH
chmod +x "$FAKEBIN/herdr"
export HERDR_LAB_SESSION="$S"

# --- lab home ---------------------------------------------------------------
"$ROOT/bin/fm-lab-home.sh" create "$LAB" || exit 1
printf '%s\n' herdr > "$LAB/config/backend"
printf '%s\n' manual > "$LAB/config/backlog-backend"
touch "$LAB/config/herdr-presentation-spaces"
LAB_REAL=$(cd "$LAB" && pwd -P)

# --- fixture: 1 focused anchor + 34 grammar candidates ----------------------
ANCHOR=$(lab workspace create --cwd "$LAB" --label captain-anchor --focus) || exit 1
ANCHOR_WS=$(printf '%s' "$ANCHOR" | jq -r '.result.workspace.workspace_id')
ANCHOR_TAB=$(printf '%s' "$ANCHOR" | jq -r '.result.tab.tab_id')

for i in $(seq 1 33); do
  tok=$(printf 'sonar%017d' "$i")
  lab workspace create --cwd "$LAB" --label "└ sonar-$i · p:$tok" --no-focus >/dev/null || exit 1
done
TOK=$(printf 'restored%014d' 1)
CAND=$(lab workspace create --cwd "$LAB" --label "└ zz-restored-idle-shell · p:$TOK" --no-focus) || exit 1
WS=$(printf '%s' "$CAND" | jq -r '.result.workspace.workspace_id')
PANE=$(printf '%s' "$CAND" | jq -r '.result.root_pane.pane_id')

# --- fixture: 65 journals (64 v2 fillers + 1 v1 exact match) -----------------
for i in $(seq 1 64); do
  tok=$(printf 'filler%016d' "$i")
  {
    printf 'version=2\n'
    printf 'task_id=filler-%02d\n' "$i"
    printf 'projection_id=%s\n' "$tok"
    printf 'home=%s\n' "$LAB_REAL"
    printf 'session=%s\n' "$S"
    printf 'workspace_id=f%d\n' "$i"
    printf 'tab_id=f%d:t1\n' "$i"
    printf 'pane_id=f%d:p1\n' "$i"
    printf 'parent_workspace_id=%s\n' "$ANCHOR_WS"
    printf 'parent_label=captain-anchor\n'
    printf 'workspace_label=└ filler-%02d · p:%s\n' "$i" "$tok"
    printf 'task_label=fm-filler-%02d\n' "$i"
  } > "$LAB/state/filler-$i.herdr-presentation"
done
{
  printf 'version=1\n'
  printf 'task_id=zz-restored-idle-shell\n'
  printf 'projection_id=%s\n' "$TOK"
} > "$LAB/state/zz-restored-idle-shell.herdr-presentation"

# --- wait for the matching candidate to become a childless idle shell -------
production_process_proof() {
  FM_HOME="$LAB" FM_BACKEND=herdr HERDR_SESSION="$S" \
    FM_HERDR_SESSION_CLEANUP_SOURCE_ONLY=1 PATH="$FAKEBIN:$HERDR_ORIGINAL_PATH" \
    bash -c '. "$1"; fm_backend_herdr_pane_idle_shell_pid "$2" "$3" >/dev/null' \
      _ "$ROOT/bin/fm-herdr-session-cleanup.sh" "$S" "$PANE"
}
attempt=0
while [ "$attempt" -lt 100 ]; do
  production_process_proof && break
  sleep 0.1
  attempt=$((attempt + 1))
done
[ "$attempt" -lt 100 ] || { say "matching candidate pane never converged"; exit 1; }

record_fixture() {
  printf 'journals: %s\n' "$(find "$LAB/state" -name '*herdr-presentation' | wc -l | tr -d ' ')"
  printf 'workspaces: %s\n' "$(lab workspace list | jq '.result.workspaces | length')"
  printf 'matching workspace present: %s\n' \
    "$(lab workspace list | jq --arg ws "$WS" '[.result.workspaces[] | select(.workspace_id == $ws)] | length')"
  printf 'focused workspace: %s\n' \
    "$(lab workspace list | jq -r '[.result.workspaces[] | select(.focused == true)] | .[0].label')"
  printf 'workspace order:\n'
  lab workspace list | jq -r '.result.workspaces[].label'
}

say "fixture built"
record_fixture | tee "$EV/01-fixture-before.txt"

# --- 1. BASE revision full locked session start (reported failure) -----------
say "base revision locked session start (120s bound)"
BASEBIN=$TMP/base-bin
mkdir -p "$BASEBIN"
( cd "$ROOT" && git archive "$BASE_COMMIT" bin ) | tar -x -C "$BASEBIN" || exit 1
t0=$(now)
env FM_HOME="$LAB" HERDR_SESSION="$S" FM_ROOT_OVERRIDE="$ROOT" \
  PATH="$FAKEBIN:$HERDR_ORIGINAL_PATH" \
  bash "$BASEBIN/bin/fm-session-start.sh" > "$EV/02-base-session-start.txt" 2>&1
base_rc=$?
t1=$(now)
printf 'base rc=%s elapsed=%ss\n' "$base_rc" "$(python3 -c "print($t1-$t0)")" | tee -a "$EV/02-base-session-start.txt"
grep -c 'STARTUP TRUNCATED - SESSION START HIT ITS 120s RUNTIME BOUND' "$EV/02-base-session-start.txt" >/dev/null \
  || { say "base run did NOT hit the runtime bound"; exit 1; }
grep 'It stopped during the' "$EV/02-base-session-start.txt" || true

say "fixture after base run (must be unmutated)"
record_fixture | tee "$EV/03-fixture-after-base.txt"
[ "$(find "$LAB/state" -name '*herdr-presentation' | wc -l | tr -d ' ')" = 65 ] \
  || { say "base run mutated journals"; exit 1; }
[ "$(lab workspace list | jq --arg ws "$WS" '[.result.workspaces[] | select(.workspace_id == $ws)] | length')" = 1 ] \
  || { say "base run mutated the candidate workspace"; exit 1; }

# --- 2. TARGET revision full locked session start ---------------------------
say "target revision locked session start"
t0=$(now)
env FM_HOME="$LAB" HERDR_SESSION="$S" FM_ROOT_OVERRIDE="$ROOT" \
  PATH="$FAKEBIN:$HERDR_ORIGINAL_PATH" \
  bash "$ROOT/bin/fm-session-start.sh" > "$EV/04-target-session-start.txt" 2>&1
target_rc=$?
t1=$(now)
printf 'target rc=%s elapsed=%ss\n' "$target_rc" "$(python3 -c "print($t1-$t0)")" | tee -a "$EV/04-target-session-start.txt"
if grep -q '^●  STARTUP TRUNCATED' "$EV/04-target-session-start.txt"; then
  say "target run truncated"; exit 1
fi
for stage in LOCK 'HOME ROLE' BOOTSTRAP 'WAKE QUEUE' 'FLEET STATE' 'NEXT STEP'; do
  grep -q "$stage" "$EV/04-target-session-start.txt" || { say "target digest missing stage $stage"; exit 1; }
done
grep -A2 '^LOCK' "$EV/04-target-session-start.txt" | head -5

say "fixture after target run (exactly the stale child retired)"
record_fixture | tee "$EV/05-fixture-after-target.txt"
[ "$(find "$LAB/state" -name '*herdr-presentation' | wc -l | tr -d ' ')" = 64 ] \
  || { say "target run removed the wrong number of journals"; exit 1; }
[ ! -e "$LAB/state/zz-restored-idle-shell.herdr-presentation" ] \
  || { say "matching journal survived"; exit 1; }
if lab pane get "$PANE" >/dev/null 2>&1; then say "stale pane survived"; exit 1; fi
if lab workspace get "$WS" >/dev/null 2>&1; then say "stale workspace survived"; exit 1; fi
[ "$(lab workspace list | jq '.result.workspaces | length')" = 34 ] \
  || { say "unexpected workspace count after cleanup"; exit 1; }
[ "$(lab workspace list | jq -r '[.result.workspaces[] | select(.focused == true)] | .[0].label')" = captain-anchor ] \
  || { say "anchor focus not preserved"; exit 1; }

# --- 3. TARGET cleanup pass alone, timed -------------------------------------
say "target cleanup pass alone (64 journals, 33 unmatched candidates)"
t0=$(now)
env FM_HOME="$LAB" HERDR_SESSION="$S" FM_ROOT_OVERRIDE="$ROOT" \
  PATH="$FAKEBIN:$HERDR_ORIGINAL_PATH" \
  bash "$ROOT/bin/fm-herdr-session-cleanup.sh" > "$EV/06-target-cleanup-alone.txt" 2>&1
alone_rc=$?
t1=$(now)
printf 'cleanup-alone rc=%s elapsed=%ss\n' "$alone_rc" "$(python3 -c "print($t1-$t0)")" | tee -a "$EV/06-target-cleanup-alone.txt"
[ "$(find "$LAB/state" -name '*herdr-presentation' | wc -l | tr -d ' ')" = 64 ] \
  || { say "no-op pass removed journals"; exit 1; }

say "scale scenario complete"
