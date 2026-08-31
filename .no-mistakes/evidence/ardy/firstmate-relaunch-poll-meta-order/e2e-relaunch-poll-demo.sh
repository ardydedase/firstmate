#!/usr/bin/env bash
# End-to-end evidence harness for the relaunch meta-order fix
# (branch ardy/firstmate-relaunch-poll-meta-order).
#
# It reproduces the reported live failure through the real executables only:
#   1. a live claude ship task in a hermetic home (stubbed tmux session
#      provider, real git worktree, real state records),
#   2. the PR merge poll armed by the real bin/fm-pr-check.sh with a stubbed
#      gh CLI that reports the PR head sha and the PR state,
#   3. the task relaunched by the real bin/fm-control.sh <id> relaunch,
#   4. real bin/fm-watch.sh cycles that must validate and run the armed poll.
#
# Usage: e2e-relaunch-poll-demo.sh <worktree-root> <mode>
#   mode: reject-expected - the unfixed writer; the watcher must reject the
#         armed poll with 'check: rejected unauthenticated state checks' every
#         cycle, and the poll never retires.
#   mode: accept-expected - the fixed writer; the watcher must validate the
#         poll, observe the merge, and retire the poll.
#
# Not part of the repository test suite; it lives in the run's evidence
# directory and reuses the suite's hermetic stubs verbatim.
set -u

WORKTREE=${1:?usage: e2e-relaunch-poll-demo.sh <worktree-root> <mode>}
MODE=${2:?usage: e2e-relaunch-poll-demo.sh <worktree-root> <mode>}
case "$MODE" in
  reject-expected|accept-expected) ;;
  *) printf 'error: unknown mode %s\n' "$MODE" >&2; exit 2 ;;
esac

# shellcheck source=/dev/null
. "$WORKTREE/tests/lib.sh"
if [ "$ROOT" != "$WORKTREE" ]; then
  printf 'error: ROOT %s does not match the given worktree %s\n' "$ROOT" "$WORKTREE" >&2
  exit 2
fi

CONTROL="$ROOT/bin/fm-control.sh"
PR_CHECK="$ROOT/bin/fm-pr-check.sh"
WATCH="$ROOT/bin/fm-watch.sh"
REGISTER="$ROOT/bin/fm-check-register.sh"
BASE_PATH=${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
ID=demo
URL=https://github.com/example/repo/pull/21
HEAD_SHA=0123456789abcdef0123456789abcdef01234567

# The same lifecycle-modelling tmux stub as tests/fm-control-relaunch.test.sh.
make_tmux_stub() {  # <dir>
  local fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/tmux" <<'SH'
#!/usr/bin/env bash
set -u
D=$FM_FAKE_DIR
case "${1:-}" in
  send-keys)
    shift
    literal=0
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) shift 2 ;;
        -l) literal=1; shift ;;
        *) break ;;
      esac
    done
    payload=${1:-}
    if [ "$literal" = 1 ]; then
      printf '%s\n' "$payload" >> "$D/literal"
      case "$payload" in
        /exit|/quit)
          printf 'zsh' > "$D/command"
          [ -z "${FM_FAKE_EXIT_TRANSPORT_FAIL_AFTER_STOP:-}" ] || exit 1
          ;;
        *'encode launch-brief'*)
          cat "$D/becomes" > "$D/command"
          [ -z "${FM_FAKE_LAUNCH_TRANSPORT_FAIL_AFTER_START:-}" ] || exit 1
          ;;
      esac
    else
      printf '%s\n' "$payload" >> "$D/keys"
    fi
    exit 0 ;;
  display-message)
    for a in "$@"; do
      case "$a" in
        *cursor_y*) printf '1\n'; exit 0 ;;
        *pane_current_command*) cat "$D/command"; printf '\n'; exit 0 ;;
        *pane_current_path*) cat "$D/cwd"; printf '\n'; exit 0 ;;
      esac
    done
    printf 'fakepane\n'; exit 0 ;;
  capture-pane) printf '\xe2\x95\xad\xe2\x94\x80\xe2\x94\x80\xe2\x95\xae\n'; exit 0 ;;
  list-windows) [ -f "$D/windows" ] && cat "$D/windows"; exit 0 ;;
esac
exit 0
SH
  chmod +x "$fb/tmux"
  cat > "$fb/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fb/sleep"
}

# The same forge-CLI stubs as tests/fm-pr-check-security.test.sh: gh answers
# the head sha and the PR state, glab and gh-axi answer their own contracts.
make_forge_stubs() {  # <dir>
  local fb="$1/fakebin"
  cat > "$fb/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GH_LOG"
case " $* " in
  *" headRefOid "*) printf '%s\n' "${FM_TEST_GH_HEAD:-0123456789abcdef0123456789abcdef01234567}" ;;
  *" state "*)
    [ "${FM_TEST_GH_FAIL:-0}" = 0 ] || exit 1
    printf '%s\n' "${FM_TEST_GH_STATE:-OPEN}"
    ;;
esac
exit 0
SH
  cat > "$fb/gh-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GH_AXI_LOG"
case "${1:-} ${2:-}" in
  "pr view")
    [ "$#" -eq 5 ] && [ "${4:-}" = --repo ] || exit 2
    printf 'pull_request:\n  number: %s\n  state: %s\n' "$3" "${FM_TEST_GH_MERGE_STATE:-merged}"
    ;;
esac
exit "${FM_TEST_GH_AXI_RC:-0}"
SH
  cat > "$fb/glab" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GLAB_LOG"
[ "${FM_TEST_GLAB_FAIL:-0}" = 0 ] || exit 1
printf 'title:\tfixture merge request\nstate:\t%s\nauthor:\tsomeone\n' "${FM_TEST_GLAB_STATE:-opened}"
SH
  chmod +x "$fb/gh" "$fb/gh-axi" "$fb/glab"
}

# The same bounded single-cycle watcher driver as tests/fm-pr-check-security.test.sh.
run_watcher_bounded() {
  local home=$1 fakebin=$2 check_interval=${FM_TEST_CHECK_INTERVAL:-0} watch_root=${FM_TEST_WATCH_ROOT:-$ROOT}
  shift 2
  perl -e 'my $pid=fork; die unless defined $pid; if (!$pid) { exec @ARGV } local $SIG{ALRM}=sub { kill "TERM", $pid; waitpid $pid, 0; exit 124 }; alarm 10; waitpid $pid, 0; alarm 0; exit($? >> 8)' \
    env FM_HOME="$home" FM_ROOT_OVERRIDE="$watch_root" FM_CHECK_INTERVAL="$check_interval" FM_CHECK_TIMEOUT=1 \
      FM_POLL=0.02 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 PATH="$fakebin:$BASE_PATH" "$WATCH" "$@"
}

ack_watcher_cycle() {  # <state>
  local state=$1 err sequence generation
  err="$state/.test-wake-drain.err"
  FM_STATE_OVERRIDE="$state" "$ROOT/bin/fm-wake-drain.sh" >/dev/null 2> "$err" || return 1
  sequence=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9][0-9]*\) --recovery-generation [A-Za-z0-9._-][A-Za-z0-9._-]*$/\1/p' "$err")
  generation=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through [0-9][0-9]* --recovery-generation \([A-Za-z0-9._-][A-Za-z0-9._-]*\)$/\1/p' "$err")
  rm -f "$err"
  [ -n "$sequence" ] && [ -n "$generation" ] || return 1
  FM_STATE_OVERRIDE="$state" "$ROOT/bin/fm-wake-drain.sh" --ack-through "$sequence" \
    --recovery-generation "$generation"
}

banner() { printf '\n========== %s ==========\n' "$1"; }
show_meta() {  # <meta>
  printf -- '--- %s ---\n' "$1"
  awk '{ printf "  %2d  %s\n", NR, $0 }' "$1"
}

TMP_ROOT=$(fm_test_tmproot "fm-e2e-$MODE")
mkdir -p "$TMP_ROOT"
TMP_ROOT=$(cd "$TMP_ROOT" && pwd)
demo_cleanup() {
  rm -rf "$TMP_ROOT" "/tmp/fm-$ID"
  fm_test_cleanup
}
trap demo_cleanup EXIT HUP INT TERM

# ---------------------------------------------------------------- setup ----
banner "setup: hermetic home with a live claude ship task"
printf 'worktree: %s\n' "$WORKTREE"
printf 'head:     %s\n' "$(git -C "$WORKTREE" rev-parse HEAD)"
printf 'writer:   bin/fm-spawn.sh '
if git -C "$WORKTREE" diff --quiet HEAD -- bin/fm-spawn.sh; then
  printf 'matches HEAD (fixed writer)\n'
else
  printf 'differs from HEAD (base writer reverted for this run)\n'
fi
printf 'mode:     %s\n' "$MODE"

dir="$TMP_ROOT/case"
home="$dir/home"
state="$home/state"
mkdir -p "$home/state" "$home/data/$ID" "$dir/fake" "$dir/root/bin"
: > "$dir/fake/literal"
: > "$dir/fake/keys"
printf 'claude' > "$dir/fake/command"
printf 'claude' > "$dir/fake/becomes"
printf '%s\n' "fm-$ID" > "$dir/fake/windows"
make_tmux_stub "$dir"
make_forge_stubs "$dir"
: > "$dir/gh.log"
: > "$dir/gh-axi.log"
: > "$dir/glab.log"
# A no-op guard root for the arming entry point, as in the security suite.
printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/root/bin/fm-guard.sh"
chmod +x "$dir/root/bin/fm-guard.sh"

fm_git_worktree "$dir/proj" "$dir/wt" "task-$ID"
printf '# brief for %s\n\nDo the thing.\n' "$ID" > "$home/data/$ID/brief.md"
{
  echo "window=fmses:fm-$ID"
  echo "endpoint_task_id=$ID"
  echo "worktree=$dir/wt"
  echo "project=$dir/proj"
  echo "harness=claude"
  echo "kind=ship"
  echo "mode=no-mistakes"
  echo "yolo=off"
  echo "tasktmp=$dir/tasktmp"
  echo "model=default"
  echo "effort=default"
} > "$state/$ID.meta"
printf '%s' "$dir/wt" > "$dir/fake/cwd"
show_meta "$state/$ID.meta"

# ----------------------------------------------------------------- arm ----
banner "arm the PR merge poll via the real fm-pr-check.sh (stubbed gh CLI)"
printf '$ fm-pr-check.sh %s %s\n' "$ID" "$URL"
set +e
env PATH="$dir/fakebin:$BASE_PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$dir/root" \
  FM_TEST_GH_LOG="$dir/gh.log" FM_TEST_GH_AXI_LOG="$dir/gh-axi.log" \
  FM_TEST_GLAB_LOG="$dir/glab.log" FM_TEST_GH_STATE=OPEN FM_TEST_GH_HEAD="$HEAD_SHA" \
  "$PR_CHECK" "$ID" "$URL"
arm_rc=$?
set -e
[ "$arm_rc" -eq 0 ] || { printf 'error: arming failed (rc=%s)\n' "$arm_rc" >&2; exit 1; }
show_meta "$state/$ID.meta"
printf 'poll artifacts: '
ls "$state/$ID.check.sh" "$state/$ID.pr-poll" "$state/$ID.pr-poll-registration" \
  | sed "s|^$TMP_ROOT/||" | tr '\n' ' '
printf '\n'

# ------------------------------------------------------------ relaunch ----
banner "relaunch the task via the real fm-control.sh (the reported live command)"
printf '$ fm-control.sh %s relaunch --note "mid-review relaunch"\n' "$ID"
set +e
env PATH="$dir/fakebin:$PATH" FM_HOME="$home" FM_FAKE_DIR="$dir/fake" \
  FM_SPAWN_NO_GUARD=1 GROK_HOME="$dir/grokhome" \
  FM_CONTROL_POLL=0.01 FM_CONTROL_EXIT_WAIT=0.05 FM_CONTROL_LAUNCH_WAIT=0.05 \
  "$CONTROL" "$ID" relaunch --note "mid-review relaunch"
relaunch_rc=$?
set -e
printf 'relaunch exit status: %s\n' "$relaunch_rc"
[ "$relaunch_rc" -eq 0 ] || { printf 'error: relaunch failed\n' >&2; exit 1; }
show_meta "$state/$ID.meta"
if awk '/^pr=/{p=1} p && /^control_relaunch_tx=/{found=1} END {exit !found}' \
     "$state/$ID.meta"; then
  printf 'meta shape: control_relaunch_tx= was written AFTER the pr= identity line\n'
else
  printf 'meta shape: control_relaunch_tx= was written BEFORE the pr= identity line\n'
fi

# ------------------------------------------------------------- watcher ----
banner "watcher cycle 1 via the real fm-watch.sh (gh reports the PR MERGED)"
rm -f "$state/.last-check"
printf '$ FM_TEST_GH_STATE=MERGED fm-watch.sh\n'
set +e
FM_TEST_GH_STATE=MERGED FM_TEST_GH_LOG="$dir/gh.log" FM_TEST_GH_AXI_LOG="$dir/gh-axi.log" \
  FM_TEST_GLAB_LOG="$dir/glab.log" \
  run_watcher_bounded "$home" "$dir/fakebin" > "$dir/watch-1.out" 2> "$dir/watch-1.err"
watch1_rc=$?
set -e
printf 'watcher exit status: %s\n' "$watch1_rc"
printf 'watcher stdout:\n'
sed 's/^/  /' "$dir/watch-1.out"
[ -s "$dir/watch-1.err" ] && { printf 'watcher stderr:\n'; sed 's/^/  /' "$dir/watch-1.err"; }

if [ "$MODE" = reject-expected ]; then
  # The reported symptom: the poll is rejected every cycle.
  ack_watcher_cycle "$state" || { printf 'error: could not ack cycle 1\n' >&2; exit 1; }
  banner "watcher cycle 2 via the real fm-watch.sh (poll rejected every cycle)"
  rm -f "$state/.last-check"
  printf '$ FM_TEST_GH_STATE=MERGED fm-watch.sh\n'
  set +e
  FM_TEST_GH_STATE=MERGED FM_TEST_GH_LOG="$dir/gh.log" FM_TEST_GH_AXI_LOG="$dir/gh-axi.log" \
    FM_TEST_GLAB_LOG="$dir/glab.log" \
    run_watcher_bounded "$home" "$dir/fakebin" > "$dir/watch-2.out" 2> "$dir/watch-2.err"
  watch2_rc=$?
  set -e
  printf 'watcher exit status: %s\n' "$watch2_rc"
  printf 'watcher stdout:\n'
  sed 's/^/  /' "$dir/watch-2.out"
  [ -s "$dir/watch-2.err" ] && { printf 'watcher stderr:\n'; sed 's/^/  /' "$dir/watch-2.err"; }
  ack_watcher_cycle "$state" || { printf 'error: could not ack cycle 2\n' >&2; exit 1; }
else
  # With the fix, the merged poll is validated, observed, and retired, and the
  # next cycle reaches an ordinary custom check with no rejection at all.
  ack_watcher_cycle "$state" || { printf 'error: could not ack cycle 1\n' >&2; exit 1; }
  printf '#!/usr/bin/env bash\nprintf "stop-cycle\\n"\n' > "$state/z-stop.check.sh"
  chmod 0700 "$state/z-stop.check.sh"
  env FM_HOME="$home" "$REGISTER" z-stop >/dev/null
  banner "watcher cycle 2 via the real fm-watch.sh (ordinary check, no rejection)"
  rm -f "$state/.last-check"
  printf '$ FM_TEST_GH_STATE=MERGED fm-watch.sh\n'
  set +e
  FM_TEST_GH_STATE=MERGED FM_TEST_GH_LOG="$dir/gh.log" FM_TEST_GH_AXI_LOG="$dir/gh-axi.log" \
    FM_TEST_GLAB_LOG="$dir/glab.log" \
    run_watcher_bounded "$home" "$dir/fakebin" > "$dir/watch-2.out" 2> "$dir/watch-2.err"
  watch2_rc=$?
  set -e
  printf 'watcher exit status: %s\n' "$watch2_rc"
  printf 'watcher stdout:\n'
  sed 's/^/  /' "$dir/watch-2.out"
  [ -s "$dir/watch-2.err" ] && { printf 'watcher stderr:\n'; sed 's/^/  /' "$dir/watch-2.err"; }
  ack_watcher_cycle "$state" || { printf 'error: could not ack cycle 2\n' >&2; exit 1; }
fi

# -------------------------------------------------------------- evidence ----
banner "poll state after the watcher cycles"
printf 'forge calls the poll made (gh.log):\n'
sed 's/^/  $ gh /' "$dir/gh.log"
if [ -e "$state/$ID.check.sh" ]; then
  printf 'armed poll still present (never retired): %s\n' "$state/$ID.check.sh"
else
  printf 'armed poll retired by the watcher: state/%s.check.sh is gone\n' "$ID"
fi
show_meta "$state/$ID.meta"

# -------------------------------------------------------------- verdict ----
banner "verdict ($MODE)"
rejection='check: rejected unauthenticated state checks'
if [ "$MODE" = reject-expected ]; then
  grep -qF "$rejection" "$dir/watch-1.out" && grep -qF "$rejection" "$dir/watch-2.out" \
    && [ -e "$state/$ID.check.sh" ] \
    && { printf 'RESULT: the armed PR merge poll was rejected every cycle, as the unfixed writer causes\n'; exit 0; }
  printf 'RESULT: UNEXPECTED - the unfixed writer did not reproduce the rejection\n' >&2
  exit 1
fi
grep -qF "$rejection" "$dir/watch-1.out" && { printf 'RESULT: UNEXPECTED - the fixed writer still produced a rejection\n' >&2; exit 1; }
grep -qF "$ID.check.sh: merged" "$dir/watch-1.out" \
  && [ ! -e "$state/$ID.check.sh" ] \
  && { printf 'RESULT: the armed PR merge poll survived the relaunch, was validated, observed the merge, and retired\n'; exit 0; }
printf 'RESULT: UNEXPECTED - the fixed writer did not complete the merged-poll lifecycle\n' >&2
exit 1
