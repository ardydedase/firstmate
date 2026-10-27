#!/usr/bin/env bash
# Mutation negative control: temporarily patch bin/fm-fleet-snapshot.sh so
# prefetch_task_current_states EXPORTS the per-task captured crew-state override
# paths into the calling shell at dispatch (the pre-fix leak shape: a sourced
# snapshot leaves a stale captured path in the session shell), expect the
# branch's new regression test to FAIL, then restore and expect green.
set -u
WT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XHTF5DAY4XYNGXRNTA9BB4
EV=/Users/adedase/.no-mistakes/evidence/01M5XHTF5DAY4XYNGXRNTA9BB4
cd "$WT" || exit 1
exec > "$EV/mutation-control.txt" 2>&1
echo "=== mutation control at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "worktree HEAD: $(git rev-parse HEAD)"
echo "--- 1. product tree clean before mutation (expect no output) ---"
git status --short
echo "--- 2. apply the leaky mutant: prefetch_task_current_states exports the"
echo "      captured FM_CREW_STATE_META_OVERRIDE / FM_CREW_STATE_STATUS_OVERRIDE"
echo "      into the CALLING shell at task dispatch (stale captured path remains"
echo "      after the snapshot returns; the crew_state_json env prefix is untouched) ---"
python3 - <<'PY'
p = 'bin/fm-fleet-snapshot.sh'
s = open(p).read()
anchor = '''    meta=${SNAPSHOT_TASK_METAS[index]}
    id=$(basename "$meta" .meta)
    prefetch_task_observations "$meta" "$id" &
'''
leak = '''    meta=${SNAPSHOT_TASK_METAS[index]}
    id=$(basename "$meta" .meta)
    FM_CREW_STATE_META_OVERRIDE="$SNAPSHOT_TASK_DIR/$id.meta"
    FM_CREW_STATE_STATUS_OVERRIDE="$SNAPSHOT_TASK_DIR/$id.status"
    export FM_CREW_STATE_META_OVERRIDE FM_CREW_STATE_STATUS_OVERRIDE
    prefetch_task_observations "$meta" "$id" &
'''
assert s.count(anchor) == 1, "anchor not unique"
open(p, 'w').write(s.replace(anchor, leak, 1))
print("mutant applied: captured overrides exported at prefetch dispatch")
PY
echo "--- 3. suite against the leaky mutant (expect the new test to FAIL) ---"
bash tests/fm-fleet-snapshot-view.test.sh
echo "mutant suite exit=$?"
echo "--- 4. restore the product file ---"
git checkout -- bin/fm-fleet-snapshot.sh
echo "restored; dirty files now: [$(git status --short | tr '\n' ' ')]"
echo "--- 5. suite at the restored target commit (expect green) ---"
bash tests/fm-fleet-snapshot-view.test.sh
echo "restored suite exit=$?"
echo "--- 6. final tree state ---"
git status --short && echo "(clean)"
