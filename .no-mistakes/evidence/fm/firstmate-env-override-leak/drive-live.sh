#!/usr/bin/env bash
# Live lab-home drive of the three crew-state override scenarios for branch
# fm/firstmate-env-override-leak (base 8818a80, target b8647d2).
#
# Follows the repo's disposable-lab contract: mktemp lab home,
# bin/fm-lab-home.sh create, private tmux socket dir under the lab, every pane
# driven only through that socket, and the lab removed in this same run
# (exit-time trap). The three scenarios below run the real product scripts
# inside a real product session shell (tmux 'primary' pane launched with
# FM_HOME pointing at the lab home).
set -u

W=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5KXBEMGNCKZK289WMESYWAM
BIN="$W/bin"
OUTDIR=${1:?usage: drive-live.sh <outdir>}
mkdir -p "$OUTDIR"
SUMMARY="$OUTDIR/live-lab-assertions.txt"
: > "$SUMMARY"

case "${TMPDIR:-/tmp}" in *[[:space:]]*) echo "driver: TMPDIR has whitespace; abort" >&2; exit 1 ;; esac

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX") || exit 1
IDX=0
FAILURES=0

cleanup() {
  TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab kill-server >/dev/null 2>&1 || true
  "$BIN/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1 || true
  rm -rf "$LAB"
}
trap cleanup EXIT

"$BIN/fm-lab-home.sh" create "$LAB" >/dev/null || { echo "driver: lab create failed" >&2; exit 1; }
mkdir -p "$LAB/tmux" || exit 1

note() { printf '%s\n' "$*" | tee -a "$SUMMARY" >&2; }
failout() { note "NOT-OK - $*"; FAILURES=$((FAILURES + 1)); }
judge() { # <file> <needle> <label> [min-count]
  local file=$1 needle=$2 label=$3 min=${4:-1} count=0
  # Only judge executed OUTPUT lines; prompt-prefixed typed-terminal echo lines
  # (bash-3.2$ ...) include the printed needle text verbatim and must not
  # count as pass evidence.
  [ -f "$file" ] && { count=$(grep -v '^bash-3\.[0-9]*\$ ' "$file" 2>/dev/null | grep -Fc -- "$needle" 2>/dev/null) || count=0; }
  if [ "$count" -ge "$min" ]; then
    note "ok - $label"
  else
    failout "$label (in ${file#$OUTDIR/}: found $count, wanted >= $min)"
  fi
}

judge_no_nonzero_rc() { # <file> <label>
  local file=$1 label=$2 count
  count=$(grep -v '^bash-3\.[0-9]*\$ ' "$file" 2>/dev/null | grep -Ec -- '__MK[0-9]+__ [1-9][0-9]*' 2>/dev/null) || count=0
  if [ "$count" -eq 0 ]; then
    note "ok - $label"
  else
    failout "$label ($count pane steps returned nonzero rc in ${file#$OUTDIR/})"
  fi
}

T() { TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab "$@"; }

# ---------------------------------------------------------------------------
# Seed the lab home with one real in-flight crew task.
# ---------------------------------------------------------------------------
seed() {
  mkdir -p "$LAB/state" "$LAB/data/leaktask" "$LAB/projects/leaktask-wt" \
    "$LAB/captured-1" "$LAB/captured-2"
  cat > "$LAB/data/backlog.md" <<EOF
## In flight
- [ ] leaktask - Leak Task $LAB/data/leaktask/report.md (repo: alpha) (kind: scout) (since 2026-07-07)
EOF
  printf '# Report\n' > "$LAB/data/leaktask/report.md"
  cat > "$LAB/state/leaktask.meta" <<EOF
window=firstmate:fm-leaktask
worktree=$LAB/projects/leaktask-wt
project=alpha
harness=claude
kind=scout
mode=scout
yolo=off
EOF
  printf 'working: live status from the lab\n' > "$LAB/state/leaktask.status"
  # Stale captured generation whose worktree no longer exists: an honored META
  # override must make crew-state read THIS file and report the torn-down
  # worktree instead of the live meta.
  cat > "$LAB/captured-1/leaktask.meta" <<EOF
window=firstmate:fm-leaktask
worktree=$LAB/projects/torn-down-leaktask-wt
project=alpha
harness=claude
kind=scout
mode=scout
yolo=off
EOF
  # Stale captured status of an unrelated generation.
  printf 'failed: stale captured stakes\n' > "$LAB/captured-2/leaktask.status"
  # Arm/commit the claude busy event as idle so the crew-state read falls
  # through to the status log deterministically (claude-hook is a trusted
  # busy source for the claude harness).
  local gen
  gen=$("$BIN/fm-busy-event.sh" arm "$LAB/state" leaktask) || return 1
  "$BIN/fm-busy-event.sh" apply "$LAB/state" leaktask idle --gen "$gen" \
    --source claude-hook --event stop >/dev/null || return 1
}

seed || { failout "lab seed failed"; exit 1; }
note "lab home: $LAB (mktemp; removed by this run's exit trap)"

# ---------------------------------------------------------------------------
# Launch helpers. parent_env: the exact runbook env prefix for launching a
# product session from a parent shell; scenario overrides added via eval.
# ---------------------------------------------------------------------------
PARENT_ENV_PREFIX='env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_PROJECTS_OVERRIDE -u FM_CONFIG_OVERRIDE'

launch_sessions() { # <meta-override|-> <status-override|->
  local meta=$1 status=$2 pre="$PARENT_ENV_PREFIX"
  [ "$meta" != "-" ] && pre="$pre FM_CREW_STATE_META_OVERRIDE=$meta"
  [ "$status" != "-" ] && pre="$pre FM_CREW_STATE_STATUS_OVERRIDE=$status"
  T kill-server >/dev/null 2>&1 || true
  eval "$pre TMUX_TMPDIR='$LAB/tmux' tmux -L fm-lab new-session -d -s firstmate -n fm-leaktask -x 220 -y 50 'sleep 600'" \
    || { failout "endpoint session launch failed"; return 1; }
  eval "$pre TMUX_TMPDIR='$LAB/tmux' tmux -L fm-lab new-session -d -s primary -x 220 -y 50 -c '$W' -e FM_HOME='$LAB' bash" \
    || { failout "primary session shell launch failed"; return 1; }
  local grid
  grid=$(T display-message -p -t primary '#{window_width}x#{window_height}' 2>/dev/null)
  case "$grid" in
    0x0|"") failout "primary pane grid is '$grid'" ;;
    *) note "ok - primary pane launched on lab socket fm-lab, grid non-zero ($grid)" ;;
  esac
  return 0
}

pane() { # <command typing target text>
  IDX=$((IDX + 1))
  T send-keys -t primary -l "$1 ; echo __MK${IDX}__ \$?"
  T send-keys -t primary Enter
  local cur i=0
  while [ "$i" -lt 400 ]; do
    cur=$(T capture-pane -p -t primary -S -3000 2>/dev/null)
    case "$cur" in *"__MK${IDX}__ "[0-9]*) return 0 ;; esac
    i=$((i + 1)); sleep 0.2
  done
  failout "pane marker __MK${IDX}__ never appeared"
  return 1
}

pane_text() { T capture-pane -p -t primary -S -3000 2>/dev/null; }

scp_lab() { # <lab-relative> <evidence-name>
  cp "$LAB/$1" "$OUTDIR/$2" 2>/dev/null \
    || { cp "$LAB/${1%%/*}/$(basename "$1")" "$OUTDIR/$2" 2>/dev/null; } \
    || failout "could not copy $1 to evidence"
}

WORKING_LIVE='state: working · source: status-log · live status from the lab'

# ===========================================================================
# Scenario 1: FM_CREW_STATE_META_OVERRIDE set in the parent environment.
# Scoping must hold: override honored for crew-state meta reads, no override
# leakage into the session shell, snapshot child still reads live state.
# ===========================================================================
echo "== Scenario 1: META override in parent environment ==" >&2
launch_sessions "$LAB/captured-1/leaktask.meta" - || true
S1PANE="$OUTDIR/live-lab-s1-meta-override-pane-transcript.txt"

pane 'printf "S1-ENTRY meta=[%s] status=[%s] fmhome=[%s]\n" "${FM_CREW_STATE_META_OVERRIDE-__UNSET__}" "${FM_CREW_STATE_STATUS_OVERRIDE-__UNSET__}" "$FM_HOME"'
pane 'n=$(env | grep -c "^FM_CREW_STATE_.*OVERRIDE=" || true); printf "S1-OVERRIDE-VAR-COUNT=%s\n" "$n"'
pane 'echo "S1-CONTROL-READ (override removed for this child only):"'
pane 'env -u FM_CREW_STATE_META_OVERRIDE '"$BIN"'/fm-crew-state.sh leaktask'
pane 'echo "S1-OVERRIDE-READ (parent override honored):"'
pane "$BIN/fm-crew-state.sh leaktask"
pane "$BIN/fm-fleet-snapshot.sh --json > \"\$FM_HOME/s1.json\"; printf \"S1-SNAPSHOT-RC=%s\\n\" \"\$?\""
pane 'printf "S1-AFTER meta=[%s] status=[%s]\n" "${FM_CREW_STATE_META_OVERRIDE-__UNSET__}" "${FM_CREW_STATE_STATUS_OVERRIDE-__UNSET__}"'
pane 'n=$(env | grep -c "^FM_CREW_STATE_.*OVERRIDE=" || true); printf "S1-AFTER-OVERRIDE-VAR-COUNT=%s\n" "$n"'
pane '[ "${FM_CREW_STATE_META_OVERRIDE-__X__}" = "$FM_HOME/captured-1/leaktask.meta" ] && echo "ok - S1: session shell keeps exactly the parent-set meta override - no captured-path leak" || echo "NOT-OK - S1: meta env is [${FM_CREW_STATE_META_OVERRIDE-__UNSET__}]"'
pane '[ -z "${FM_CREW_STATE_STATUS_OVERRIDE+Z}" ] && echo "ok - S1: status override never materialized in the session shell" || echo "NOT-OK - S1: status override materialized [${FM_CREW_STATE_STATUS_OVERRIDE}]"'
pane 'jq -e '\''.tasks[]|select(.id=="leaktask")|(.current_state.state=="working" and .current_state.source=="status-log" and .current_state.detail=="live status from the lab" and .endpoint.exists==true)'\'' "$FM_HOME/s1.json" >/dev/null && echo "ok - S1: snapshot child read the live crew state despite the ambient meta override" || echo "NOT-OK - S1: snapshot child read polluted by ambient override"'
pane 'echo "S1-REPEAT-READ (still the parent override after the snapshot):"'
pane "$BIN/fm-crew-state.sh leaktask"
pane "$BIN/fm-fleet-view.sh > \"\$FM_HOME/s1-view.txt\" 2>&1; printf \"S1-VIEW-RC=%s\\n\" \"\$?\""
pane 'sed -n "1,18p" "$FM_HOME/s1-view.txt"; echo "S1-VIEW-SHOWN"'

pane_text > "$S1PANE"
judge "$S1PANE" "S1-ENTRY meta=[$LAB/captured-1/leaktask.meta] status=[__UNSET__] fmhome=[$LAB]" "S1: session shell inherited the parent-set META override verbatim"
judge "$S1PANE" "S1-AFTER meta=[$LAB/captured-1/leaktask.meta] status=[__UNSET__]" "S1: META override in the session shell stayed exactly the parent-set value after the snapshot ran"
judge "$S1PANE" "S1-AFTER-OVERRIDE-VAR-COUNT=1" "S1: exactly one crew-state override variable exists in the session shell env after the snapshot"
judge "$S1PANE" "$WORKING_LIVE" "S1: control crew-state read with override removed shows live meta behavior (working from status log)"
judge "$S1PANE" "state: unknown · source: none · worktree gone (torn down?)" "S1: crew-state honored the META override (torn-down worktree of the captured generation)" 2
judge "$S1PANE" "S1-SNAPSHOT-RC=0" "S1: fleet snapshot exited 0 inside the session shell"
judge "$S1PANE" "ok - S1: session shell keeps exactly the parent-set meta override - no captured-path leak" "S1: no captured-path leak into the session shell (in-shell check)"
judge "$S1PANE" "ok - S1: status override never materialized in the session shell" "S1: no status override materialized (in-shell check)"
judge "$S1PANE" "ok - S1: snapshot child read the live crew state despite the ambient meta override" "S1: snapshot child read live state despite ambient META override (in-shell check)"
judge "$S1PANE" "S1-VIEW-RC=0" "S1: fleet view render exited 0"
judge "$S1PANE" "leaktask" "S1: fleet view render mentions the crew task"
judge "$S1PANE" "S1-REPEAT-READ" "S1: repeat read driven after the snapshot"
judge_no_nonzero_rc "$S1PANE" "S1: every driven pane step returned rc 0"
scp_lab s1.json "live-lab-s1-snapshot.json"
scp_lab s1-view.txt "live-lab-s1-fleet-view-render.txt"

# ===========================================================================
# Scenario 2: FM_CREW_STATE_STATUS_OVERRIDE set in the parent environment.
# ===========================================================================
echo "== Scenario 2: STATUS override in parent environment ==" >&2
launch_sessions - "$LAB/captured-2/leaktask.status" || true
S2PANE="$OUTDIR/live-lab-s2-status-override-pane-transcript.txt"

pane 'printf "S2-ENTRY meta=[%s] status=[%s]\n" "${FM_CREW_STATE_META_OVERRIDE-__UNSET__}" "${FM_CREW_STATE_STATUS_OVERRIDE-__UNSET__}"'
pane 'n=$(env | grep -c "^FM_CREW_STATE_.*OVERRIDE=" || true); printf "S2-OVERRIDE-VAR-COUNT=%s\n" "$n"'
pane 'echo "S2-CONTROL-READ (override removed for this child only):"'
pane 'env -u FM_CREW_STATE_STATUS_OVERRIDE '"$BIN"'/fm-crew-state.sh leaktask'
pane 'echo "S2-OVERRIDE-READ (parent override honored):"'
pane "$BIN/fm-crew-state.sh leaktask"
pane "$BIN/fm-fleet-snapshot.sh --json > \"\$FM_HOME/s2.json\"; printf \"S2-SNAPSHOT-RC=%s\\n\" \"\$?\""
pane 'printf "S2-AFTER meta=[%s] status=[%s]\n" "${FM_CREW_STATE_META_OVERRIDE-__UNSET__}" "${FM_CREW_STATE_STATUS_OVERRIDE-__UNSET__}"'
pane 'n=$(env | grep -c "^FM_CREW_STATE_.*OVERRIDE=" || true); printf "S2-AFTER-OVERRIDE-VAR-COUNT=%s\n" "$n"'
pane '[ "${FM_CREW_STATE_STATUS_OVERRIDE-__X__}" = "$FM_HOME/captured-2/leaktask.status" ] && echo "ok - S2: session shell keeps exactly the parent-set status override - no captured-path leak" || echo "NOT-OK - S2: status env is [${FM_CREW_STATE_STATUS_OVERRIDE-__UNSET__}]"'
pane '[ -z "${FM_CREW_STATE_META_OVERRIDE+Z}" ] && echo "ok - S2: meta override never materialized in the session shell" || echo "NOT-OK - S2: meta override materialized [${FM_CREW_STATE_META_OVERRIDE}]"'
pane 'jq -e '\''.tasks[]|select(.id=="leaktask")|(.current_state.state=="working" and .current_state.source=="status-log" and .current_state.detail=="live status from the lab" and .endpoint.exists==true)'\'' "$FM_HOME/s2.json" >/dev/null && echo "ok - S2: snapshot child read the live crew state despite the ambient status override" || echo "NOT-OK - S2: snapshot child read polluted by ambient override"'
pane 'echo "S2-REPEAT-READ (still the parent override after the snapshot):"'
pane "$BIN/fm-crew-state.sh leaktask"

pane_text > "$S2PANE"
judge "$S2PANE" "S2-ENTRY meta=[__UNSET__] status=[$LAB/captured-2/leaktask.status]" "S2: session shell inherited the parent-set STATUS override verbatim"
judge "$S2PANE" "S2-AFTER meta=[__UNSET__] status=[$LAB/captured-2/leaktask.status]" "S2: STATUS override in the session shell stayed exactly the parent-set value after the snapshot ran"
judge "$S2PANE" "S2-AFTER-OVERRIDE-VAR-COUNT=1" "S2: exactly one crew-state override variable exists in the session shell env after the snapshot"
judge "$S2PANE" "$WORKING_LIVE" "S2: control crew-state read with override removed shows live status behavior"
judge "$S2PANE" "state: failed · source: status-log · stale captured stakes" "S2: crew-state honored the STATUS override (stale captured status)" 2
judge "$S2PANE" "S2-SNAPSHOT-RC=0" "S2: fleet snapshot exited 0 inside the session shell"
judge "$S2PANE" "ok - S2: session shell keeps exactly the parent-set status override - no captured-path leak" "S2: no captured-path leak into the session shell (in-shell check)"
judge "$S2PANE" "ok - S2: meta override never materialized in the session shell" "S2: no meta override materialized (in-shell check)"
judge "$S2PANE" "ok - S2: snapshot child read the live crew state despite the ambient status override" "S2: snapshot child read live state despite ambient STATUS override (in-shell check)"
judge "$S2PANE" "S2-REPEAT-READ" "S2: repeat read driven after the snapshot"
judge_no_nonzero_rc "$S2PANE" "S2: every driven pane step returned rc 0"
scp_lab s2.json "live-lab-s2-snapshot.json"

# ===========================================================================
# Scenario 3: neither override set at launch. Default behavior unchanged; the
# snapshot (command and sourced forms) never injects override variables; later
# crew-state reads resolve live state; explicit ambient poisoning after the
# run cannot corrupt the snapshot's own read.
# ===========================================================================
echo "== Scenario 3: no overrides at launch ==" >&2
launch_sessions - - || true
S3PANE="$OUTDIR/live-lab-s3-clean-session-shell-pane-transcript.txt"

pane 'printf "S3-ENTRY meta=[%s] status=[%s]\n" "${FM_CREW_STATE_META_OVERRIDE-__UNSET__}" "${FM_CREW_STATE_STATUS_OVERRIDE-__UNSET__}"'
pane 'n=$(env | grep -c "^FM_CREW_STATE_.*OVERRIDE=" || true); printf "S3-OVERRIDE-VAR-COUNT=%s\n" "$n"'
pane 'echo "S3-DEFAULT-READ (default behavior with no overrides):"'
pane "$BIN/fm-crew-state.sh leaktask"
pane 'echo "S3-CMD-FORM (snapshot as a plain command in the session shell):"'
pane "$BIN/fm-fleet-snapshot.sh --json > \"\$FM_HOME/s3.json\"; printf \"S3-SNAPSHOT-RC=%s\\n\" \"\$?\""
pane 'printf "S3-AFTER-CMD meta=[%s] status=[%s]\n" "${FM_CREW_STATE_META_OVERRIDE-__UNSET__}" "${FM_CREW_STATE_STATUS_OVERRIDE-__UNSET__}"'
pane 'n=$(env | grep -c "^FM_CREW_STATE_.*OVERRIDE=" || true); printf "S3-AFTER-CMD-OVERRIDE-VAR-COUNT=%s\n" "$n"'
pane '[ "${FM_CREW_STATE_META_OVERRIDE-__UNSET__}" = "__UNSET__" ] && [ "${FM_CREW_STATE_STATUS_OVERRIDE-__UNSET__}" = "__UNSET__" ] && echo "ok - S3: command-form snapshot left the session shell free of override variables" || echo "NOT-OK - S3: command-form snapshot left meta=[${FM_CREW_STATE_META_OVERRIDE-__UNSET__}] status=[${FM_CREW_STATE_STATUS_OVERRIDE-__UNSET__}]"'
pane 'echo "S3-LIVE-STATUS-REWRITE (simulating another agent updating the live status log):"'
pane 'printf "blocked: live-path-proof\n" > "$FM_HOME/state/leaktask.status"'
pane 'echo "S3-LATER-READ (later crew-state call must resolve live state, not stale captured):"'
pane "$BIN/fm-crew-state.sh leaktask"
pane "[ \"\$(\"$BIN/fm-crew-state.sh\" leaktask)\" = \"state: blocked \$(printf '\\302\\267') source: status-log \$(printf '\\302\\267') live-path-proof\" ] && echo \"ok - S3: later crew-state calls read the live status log after the snapshot\" || echo \"NOT-OK - S3: later read resolved stale state\""
pane 'echo "S3-SOURCED-FORM (snapshot sourced into the session shell):"'
pane '. '"$BIN"'/fm-fleet-snapshot.sh --json > "$FM_HOME/s3-sourced.json"; printf "S3-SOURCED-RC=%s\n" "$?"'
pane 'printf "S3-AFTER-SOURCED meta=[%s] status=[%s]\n" "${FM_CREW_STATE_META_OVERRIDE-__UNSET__}" "${FM_CREW_STATE_STATUS_OVERRIDE-__UNSET__}"'
pane 'n=$(env | grep -c "^FM_CREW_STATE_.*OVERRIDE=" || true); printf "S3-AFTER-SOURCED-OVERRIDE-VAR-COUNT=%s\n" "$n"'
pane '[ "${FM_CREW_STATE_META_OVERRIDE-__UNSET__}" = "__UNSET__" ] && [ "${FM_CREW_STATE_STATUS_OVERRIDE-__UNSET__}" = "__UNSET__" ] && echo "ok - S3: sourced snapshot left the session shell free of override variables" || echo "NOT-OK - S3: sourced snapshot left meta=[${FM_CREW_STATE_META_OVERRIDE-__UNSET__}] status=[${FM_CREW_STATE_STATUS_OVERRIDE-__UNSET__}]"'
pane 'printf "needs-decision: sourced-form-proof\n" > "$FM_HOME/state/leaktask.status"'
pane 'echo "S3-SOURCED-LATER-READ:"'
pane "$BIN/fm-crew-state.sh leaktask"
pane 'echo "S3-ADVERSARIAL-POISON (stale ambient overrides exported deliberately after the run):"'
pane 'export FM_CREW_STATE_META_OVERRIDE="$FM_HOME/captured-1/leaktask.meta" FM_CREW_STATE_STATUS_OVERRIDE="$FM_HOME/captured-2/leaktask.status"'
pane 'printf "working: poison-block-live-read\n" > "$FM_HOME/state/leaktask.status"'
pane "$BIN/fm-fleet-snapshot.sh --json > \"\$FM_HOME/s3-poison.json\"; printf \"S3-POISON-SNAPSHOT-RC=%s\\n\" \"\$?\""
pane 'jq -e '\''.tasks[]|select(.id=="leaktask")|(.current_state.state=="working" and .current_state.source=="status-log" and .current_state.detail=="poison-block-live-read")'\'' "$FM_HOME/s3-poison.json" >/dev/null && echo "ok - S3: snapshot child read live state even with deliberately poisoned ambient overrides" || echo "NOT-OK - S3: poisoned ambient overrides corrupted the snapshot read"'
pane 'unset FM_CREW_STATE_META_OVERRIDE FM_CREW_STATE_STATUS_OVERRIDE'
pane 'n=$(env | grep -c "^FM_CREW_STATE_.*OVERRIDE=" || true); printf "S3-FINAL-OVERRIDE-VAR-COUNT=%s\n" "$n"'
pane 'echo "S3-FINAL-DEFAULT-READ:"'
pane "$BIN/fm-crew-state.sh leaktask"

pane_text > "$S3PANE"
judge "$S3PANE" "S3-ENTRY meta=[__UNSET__] status=[__UNSET__]" "S3: session shell launched with neither override present"
judge "$S3PANE" "S3-OVERRIDE-VAR-COUNT=0" "S3: zero override variables at launch"
judge "$S3PANE" "$WORKING_LIVE" "S3: default crew-state behavior unchanged (working from status log)"
judge "$S3PANE" "S3-SNAPSHOT-RC=0" "S3: command-form fleet snapshot exited 0 in the session shell"
judge "$S3PANE" "S3-AFTER-CMD meta=[__UNSET__] status=[__UNSET__]" "S3: command-form snapshot left no override values in the session shell"
judge "$S3PANE" "S3-AFTER-CMD-OVERRIDE-VAR-COUNT=0" "S3: command-form snapshot appended no override variables to the env"
judge "$S3PANE" "ok - S3: command-form snapshot left the session shell free of override variables" "S3: command-form leak probes clean (in-shell check)"
judge "$S3PANE" "state: blocked · source: status-log · live-path-proof" "S3: live status log read after snapshot shows the fresh live update"
judge "$S3PANE" "ok - S3: later crew-state calls read the live status log after the snapshot" "S3: later reads resolve live state (in-shell check)"
judge "$S3PANE" "S3-SOURCED-RC=0" "S3: sourced fleet snapshot exited 0 in the session shell"
judge "$S3PANE" "S3-AFTER-SOURCED meta=[__UNSET__] status=[__UNSET__]" "S3: sourced snapshot left no override values in the session shell"
judge "$S3PANE" "S3-AFTER-SOURCED-OVERRIDE-VAR-COUNT=0" "S3: sourced snapshot appended no override variables to the env"
judge "$S3PANE" "ok - S3: sourced snapshot left the session shell free of override variables" "S3: sourced-form leak probes clean (in-shell check)"
judge "$S3PANE" "state: parked · source: status-log · sourced-form-proof" "S3: post-source live read reflects the fresh live status update"
judge "$S3PANE" "S3-POISON-SNAPSHOT-RC=0" "S3: snapshot exited 0 with deliberately poisoned ambient overrides"
judge "$S3PANE" "ok - S3: snapshot child read live state even with deliberately poisoned ambient overrides" "S3: poisoned ambient overrides cannot corrupt the snapshot's own read (in-shell check)"
judge "$S3PANE" "S3-FINAL-OVERRIDE-VAR-COUNT=0" "S3: env fully restored after unsetting the deliberate poison exports"
judge "$S3PANE" "state: working · source: status-log · poison-block-live-read" "S3: final default read resolves current live state"
judge_no_nonzero_rc "$S3PANE" "S3: every driven pane step returned rc 0"
scp_lab s3.json "live-lab-s3-snapshot.json"
scp_lab s3-poison.json "live-lab-s3-poison-snapshot.json"

OKCOUNT=$(grep -c "^ok - " "$SUMMARY" || true)
printf 'SUMMARY: ok-assertions=%s not-ok-assertions=%s\n' "$OKCOUNT" "$FAILURES" | tee -a "$SUMMARY" >&2
[ "$FAILURES" -eq 0 ] || { echo "DRIVE RESULT: FAILED ($FAILURES judge failures)" >&2; exit 1; }
echo "DRIVE RESULT: PASSED ($OKCOUNT judged ok)" >&2
exit 0
