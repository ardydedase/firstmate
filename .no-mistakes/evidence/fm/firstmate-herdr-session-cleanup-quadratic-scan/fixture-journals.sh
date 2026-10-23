#!/usr/bin/env bash
# fixture-journals.sh — 65 v2 journals bound to the lab home + lab session.
# 64 fillers (labels matching no live workspace) + 1 true candidate journal
# bound to the live stale-alive workspace/tab/pane.
set -euo pipefail
WDIR=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5M6Y5JX03BXF31FK0CC8JPF
cd "$WDIR"
EVDIR=/Users/adedase/.no-mistakes/evidence/01M5M6Y5JX03BXF31FK0CC8JPF
LAB=$(sed 's/LAB=//' /tmp/lab.path)
N=$(cat /tmp/labname.secret)
LIVETOK=$(cat /tmp/livetok.secret)
LAB_REAL=$(cd "$LAB" && pwd -P)
S="$LAB/state"

tok() { local p n t; p=$1; n=$2; t="${p}$(printf '%04d' "$n")-"; while [ ${#t} -lt 22 ]; do t="${t}X"; done; printf '%s' "$t"; }

echo "== resolving true candidate workspace endpoints"
SNAP=$(bin/fm-herdr-lab.sh run "$N" api snapshot 2>/dev/null)
LIVEID=$(printf '%s' "$SNAP" | jq -r --arg l "└ stale-alive · p:$LIVETOK" '.result.snapshot.workspaces[] | select(.label==$l) | .workspace_id')
LIVETAB=$(printf '%s' "$SNAP" | jq -r --arg w "$LIVEID" '.result.snapshot.tabs[] | select(.workspace_id==$w) | .tab_id' | head -1)
LIVEPANE=$(printf '%s' "$SNAP" | jq -r --arg t "$LIVETAB" '.result.snapshot.panes[] | select(.tab_id==$t) | .pane_id' | head -1)
echo "LIVEID=$LIVEID TAB=$LIVETAB PANE=$LIVEPANE"
printf 'workspace %s tab %s pane %s\n' "$LIVEID" "$LIVETAB" "$LIVEPANE" | tee "$EVDIR/fixture-true-candidate-id.txt"

echo "== writing 64 filler journals"
i=1
while [ "$i" -le 64 ]; do
  NN=$(printf '%02d' "$i")
  T=$(tok Jj "$i")
  printf 'version=2\ntask_id=fill-%s\nprojection_id=%s\nhome=%s\nsession=%s\nworkspace_id=wf%s\ntab_id=wf%s:t1\npane_id=wf%s:p1\nparent_workspace_id=w1\nparent_label=firstmate\nworkspace_label=└ fill-%s · p:%s\ntask_label=fm-fill-%s\n' \
    "$NN" "$T" "$LAB_REAL" "$N" "$NN" "$NN" "$NN" "$NN" "$T" "$NN" > "$S/fill-$NN.herdr-presentation"
  i=$((i+1))
done
echo wrote 64 fillers

echo "== writing the true candidate journal"
printf 'version=2\ntask_id=stale-alive\nprojection_id=%s\nhome=%s\nsession=%s\nworkspace_id=%s\ntab_id=%s\npane_id=%s\nparent_workspace_id=w1\nparent_label=firstmate\nworkspace_label=└ stale-alive · p:%s\ntask_label=fm-stale-alive\n' \
  "$LIVETOK" "$LAB_REAL" "$N" "$LIVEID" "$LIVETAB" "$LIVEPANE" "$LIVETOK" > "$S/stale-alive.herdr-presentation"
echo wrote true candidate

echo "== verify all 65 journals parse (real backend)"
FAIL=0
for j in "$S"/*.herdr-presentation; do
  id=$(basename "$j" .herdr-presentation)
  bash -c '. bin/fm-wake-lib.sh >/dev/null 2>&1; . bin/fm-backend.sh >/dev/null 2>&1; fm_backend_source herdr >/dev/null 2>&1
fm_backend_herdr_projection_journal_snapshot "$1" "$2" >/dev/null && echo ok || echo BAD' _ "$j" "$id" | grep -q '^ok$' || { echo "parse-FAIL: $id"; FAIL=1; }
done
[ "$FAIL" = 0 ] && echo "ALL 65 JOURNALS PARSE OK"
ls "$S"/*.herdr-presentation | wc -l

echo "== settle wait then idleness proof for the true pane"
sleep 3
bin/fm-herdr-lab.sh run "$N" pane process-info "$LIVEPANE" 2>/dev/null | jq -c '.result' | tee "$EVDIR/fixture-idle-proof.json"
