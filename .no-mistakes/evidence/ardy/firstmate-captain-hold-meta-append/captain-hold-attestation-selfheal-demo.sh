#!/usr/bin/env bash
# End-to-end verification of the captain-hold completion attestation rewrite
# (bin/fm-captain-hold.sh write_reviewed_attestation, commits 159c1db + 7c8c732).
#
# Reproduces the exact end-user failure and repair, against the real scripts:
#   1. A captain asks firstmate to watch a PR: fm-pr-check.sh arms a real merge
#      poll and leaves the pr=/pr_head= identity block terminal in the record.
#   2. A pre-159c1db completion writer appends its attestation pair after that
#      block (plain `>>`), which fm_pr_metadata_identity_parse rejects - the
#      armed poll can no longer validate its artifacts and silently never
#      retires.
#   3. The fixed fm-captain-hold.sh complete (an inventory-growing completion,
#      the exact path that used to strand a second pair) rewrites the record,
#      drops every stranded pair, and stages the single fresh pair before the
#      identity block - so the armed poll validates and still detects a merge.
#   4. A healthy PR-armed record keeps exactly one attestation pair across
#      inventory-growing completions, and an idempotent retry writes nothing.
#
# Fixture homes mirror tests/fm-captain-hold-lifecycle.test.sh; the fake gh
# mirrors tests/fm-pr-check-security.test.sh (headRefOid + state fields).
set -u
umask 022   # ambient umask 002 leaves fixture state dirs group-writable, which pr-lib refuses

ROOT=/home/ardy/.no-mistakes/worktrees/86574f01ec14/01M1C8V6HRT4MB82XZYPDQHCCA
WORK=$(mktemp -d /tmp/fm-attestation-demo.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

section() { printf '\n==================================================================\n%s\n==================================================================\n' "$1"; }
step()    { printf -- '\n-- %s\n' "$1"; }
fail()    { printf 'UNEXPECTED FAILURE: %s\n' "$1" >&2; exit 1; }

# --- fixture home -----------------------------------------------------------
home="$WORK/home"
mkdir -p "$home/data" "$home/state" "$home/config" "$home/projects" "$home/wt" \
  "$home/fakebin" "$WORK/root/bin"
cp "$ROOT/.tasks.toml" "$home/.tasks.toml"
printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
for tool in tmux treehouse no-mistakes gh-axi; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$home/fakebin/$tool"
done
# The fake forge CLI: answers the head SHA for arming and the state field for
# every poll cycle (FM_TEST_GH_STATE, default OPEN).
cat > "$home/fakebin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" headRefOid "*) printf '%s\n' "${FM_TEST_GH_HEAD:-0123456789abcdef0123456789abcdef01234567}" ;;
  *" state "*) printf '%s\n' "${FM_TEST_GH_STATE:-OPEN}" ;;
esac
exit 0
SH
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/root/bin/fm-guard.sh"
chmod +x "$home/fakebin"/* "$WORK/root/bin/fm-guard.sh"

tasks_in() { (cd "$home" && tasks-axi "$@"); }
captain() {
  PATH="$home/fakebin:$PATH" REAL_TASKS_AXI="$(command -v tasks-axi)" \
    FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" "$ROOT/bin/fm-captain-hold.sh" "$@"
}
pr_check() {
  FM_ROOT_OVERRIDE="$WORK/root" FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    PATH="$home/fakebin:/usr/bin:/bin:/usr/sbin:/sbin" \
    FM_TEST_GH_HEAD=0123456789abcdef0123456789abcdef01234567 \
    "$ROOT/bin/fm-pr-check.sh" "$@"
}

identity_parse() {  # <meta> -> prints VALID / REJECTED
  if ( . "$ROOT/bin/fm-pr-lib.sh" && fm_pr_metadata_identity_parse "$1" ) then
    printf 'VALID'
  else
    printf 'REJECTED'
  fi
}
poll_artifacts() {  # <id> -> prints VALID / REJECTED
  if ( . "$ROOT/bin/fm-pr-lib.sh" \
       && fm_pr_poll_artifacts_valid "$home/state" "$1" "$ROOT/bin/fm-pr-poll.sh" ) then
    printf 'VALID'
  else
    printf 'REJECTED'
  fi
}
poll_cycle() {  # runs the armed static poll program once
  PATH="$home/fakebin:/usr/bin:/bin" FM_TEST_GH_STATE="${1:-OPEN}" \
    bash "$home/state/$2.check.sh"
}
write_origin() {  # <id>
  local id=$1
  fm_write_meta() { :; }  # keep shellcheck quiet; inline below
  {
    printf 'window=firstmate:fm-%s\n' "$id"
    printf 'worktree=%s/wt\n' "$home"
    printf 'project=%s/projects/sample\n' "$home"
    printf 'harness=codex\n'
    printf 'kind=scout\n'
    printf 'mode=scout\n'
    printf 'spawn_gen=demo-%s\n' "$id"
  } > "$home/state/$id.meta"
  chmod 0600 "$home/state/$id.meta"
  printf 'done: report and visual review complete\n' > "$home/state/$id.status"
}
attestation_shape() {  # <id> -> numbered attestation/pr lines showing ordering
  grep -n -E '^(decisions_reviewed|decision_keys|pr|pr_head)=' "$home/state/$1.meta"
}

# ===========================================================================
section "SCENARIO A: repair a record polluted by the pre-fix append writer"
# ===========================================================================

step "A1. Captain opens a PR review task and asks firstmate to watch the PR"
id=sample-polluted-review
tasks_in add "$id" "Investigate armed poll repair" --kind scout --repo sample --start >/dev/null \
  || fail "could not create the origin task"
write_origin "$id"
pr_check "$id" https://github.com/example/repo/pull/42 >/dev/null 2>&1 \
  || fail "arming the merge poll failed"
printf 'armed merge poll artifacts: '
ls "$home/state" | grep -E "^$id\.(check\.sh|pr-poll|pr-poll-registration)$" | tr '\n' ' '; printf '\n'
printf 'poll cycle (PR still open, must stay silent): [%s]\n' "$(poll_cycle OPEN "$id")"
printf 'record tail after arming:\n'
tail -n 3 "$home/state/$id.meta" | sed 's/^/    /'
printf 'identity parse: %s; poll artifacts: %s\n' \
  "$(identity_parse "$home/state/$id.meta")" "$(poll_artifacts "$id")"

step "A2. The pre-159c1db completion writer appends its attestation (plain >>)"
# This is the exact line the old writer executed: a plain append with no
# knowledge of the preserved pr= identity block.
printf 'decisions_reviewed=1\ndecision_keys=\n' >> "$home/state/$id.meta"
printf 'record tail after the old append:\n'
tail -n 4 "$home/state/$id.meta" | sed 's/^/    /'
printf 'identity parse: %s; poll artifacts: %s\n' \
  "$(identity_parse "$home/state/$id.meta")" "$(poll_artifacts "$id")"
printf 'poll cycle (stays silent on every error by design): [%s]\n' "$(poll_cycle OPEN "$id")"

step "A3. The fixed completion command runs over the polluted record"
captain hold polluted-armed-call \
  --title "Choose the polluted poll fallback" --reason "captain fallback choice pending" \
  --repo sample >/dev/null || fail "could not register the captain-held task"
out=$(captain complete "$id" polluted-armed-call 2>&1) \
  || fail "the repairing completion failed: $out"
printf 'fm-captain-hold.sh complete output: %s\n' "$out"
printf 'record after the repairing completion (numbered):\n'
attestation_shape "$id" | sed 's/^/    /'
printf 'identity parse: %s; poll artifacts: %s\n' \
  "$(identity_parse "$home/state/$id.meta")" "$(poll_artifacts "$id")"
n_reviewed=$(grep -c '^decisions_reviewed=' "$home/state/$id.meta")
n_keys=$(grep -c '^decision_keys=' "$home/state/$id.meta")
recorded_keys=$(grep '^decision_keys=' "$home/state/$id.meta" | cut -d= -f2-)
last_line=$(tail -n 1 "$home/state/$id.meta")
[ "$n_reviewed" = 1 ] && [ "$n_keys" = 1 ] && [ "$recorded_keys" = "polluted-armed-call" ] \
  && [ "$last_line" = "pr_head=0123456789abcdef0123456789abcdef01234567" ] \
  || fail "repaired record shape is wrong"
printf 'exactly one attestation pair (%s), identity block terminal: OK\n' "$recorded_keys"

step "A4. The repaired armed poll still detects the merge"
printf 'poll cycle with the PR merged (must emit the merged wake): [%s]\n' \
  "$(poll_cycle MERGED "$id")"
step "A5. Re-arming the poll over the repaired record still works"
pr_check "$id" https://github.com/example/repo/pull/42 >/dev/null 2>&1 \
  || fail "re-arming over the repaired record failed"
printf 'identity parse after re-arm: %s; poll artifacts: %s\n' \
  "$(identity_parse "$home/state/$id.meta")" "$(poll_artifacts "$id")"

# ===========================================================================
section "SCENARIO B: healthy PR-armed record never accumulates pairs"
# ===========================================================================

step "B1. Fresh armed origin, first attestation lands before the identity block"
id2=sample-healthy-review
tasks_in add "$id2" "Investigate armed poll growth" --kind scout --repo sample --start >/dev/null \
  || fail "could not create the second origin task"
write_origin "$id2"
pr_check "$id2" https://github.com/example/repo/pull/43 >/dev/null 2>&1 \
  || fail "arming the second merge poll failed"
out=$(captain complete "$id2" --none 2>&1) || fail "the --none completion failed: $out"
printf 'fm-captain-hold.sh complete output: %s\n' "$out"
attestation_shape "$id2" | sed 's/^/    /'

step "B2. Two inventory-growing completions keep exactly one pair"
captain hold grow-one-call --title "Choose growth one" --reason "captain growth one pending" \
  --repo sample >/dev/null || fail "could not hold grow-one-call"
out=$(captain complete "$id2" grow-one-call 2>&1) || fail "first growing completion failed: $out"
printf 'first growing completion: %s\n' "$out"
captain hold grow-two-call --title "Choose growth two" --reason "captain growth two pending" \
  --repo sample >/dev/null || fail "could not hold grow-two-call"
out=$(captain complete "$id2" grow-one-call grow-two-call 2>&1) \
  || fail "second growing completion failed: $out"
printf 'second growing completion: %s\n' "$out"
printf 'record after both growing completions (numbered):\n'
attestation_shape "$id2" | sed 's/^/    /'
n_reviewed=$(grep -c '^decisions_reviewed=' "$home/state/$id2.meta")
n_keys=$(grep -c '^decision_keys=' "$home/state/$id2.meta")
recorded_keys=$(grep '^decision_keys=' "$home/state/$id2.meta" | cut -d= -f2-)
[ "$n_reviewed" = 1 ] && [ "$n_keys" = 1 ] \
  && [ "$recorded_keys" = "grow-one-call,grow-two-call" ] \
  || fail "the healthy record accumulated stale attestation pairs"
printf 'exactly one pair remains, inventory grown to [%s]: OK\n' "$recorded_keys"
printf 'identity parse: %s; poll artifacts: %s\n' \
  "$(identity_parse "$home/state/$id2.meta")" "$(poll_artifacts "$id2")"

step "B3. An idempotent retry writes nothing"
before=$(shasum -a 256 "$home/state/$id2.meta" | awk '{print $1}')
out=$(captain complete "$id2" grow-one-call grow-two-call 2>&1) \
  || fail "the idempotent retry failed: $out"
after=$(shasum -a 256 "$home/state/$id2.meta" | awk '{print $1}')
[ "$before" = "$after" ] || fail "the idempotent retry rewrote the record"
printf 'record byte-identical after the idempotent retry: OK\n'

printf '\nALL CHECKS PASSED\n'
