#!/usr/bin/env bash
# fixture-build-fullscale.sh — build the measured-scale fixture in the lab home.
# 64 filler journals + 1 true candidate journal (65 total), 33 grammar-matching
# filler workspaces + 1 true candidate workspace created LAST (34 candidates).
set -euo pipefail
WDIR=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5M6Y5JX03BXF31FK0CC8JPF
cd "$WDIR"
EVDIR=/Users/adedase/.no-mistakes/evidence/01M5M6Y5JX03BXF31FK0CC8JPF
LAB=$(cat /proc/self/../../proc/self/root >/dev/null 2>&1; cat /tmp/lab.path)   # placeholder, replaced below
LAB=$(sed 's/LAB=//' /tmp/lab.path)
N=$(cat /tmp/labname.secret)
LIVETOK=$(cat /tmp/livetok.secret)
LAB_REAL=$(cd "$LAB" && pwd -P)
S="$LAB/state"
WRAP="$LAB/wrapbin"

tok() { local p n t; p=$1; n=$2; t="${p}$(printf '%04d' "$n")-"; while [ ${#t} -lt 22 ]; do t="${t}X"; done; printf '%s' "$t"; }

echo "== lab=$LAB session=$N"
echo "== baseline: herdr session list"
herdr session list --json > "$EVDIR/baseline-herdr-sessions.json" 2>/dev/null || herdr session list > "$EVDIR/baseline-herdr-sessions.json"
wc -c "$EVDIR/baseline-herdr-sessions.json"

echo "== true session pre-fixture workspaces"
bin/fm-herdr-lab.sh run "$N" workspace list 2>/dev/null | jq -c '[.result.workspaces[]|{id,label}]' | tee "$EVDIR/baseline-workspaces.json"

echo "== creating 33 grammar-matching filler workspaces (created before true candidate)"
for i in $(seq -w 1 33); do
  T=$(tok Cnd "$((10#$i))")
  bin/fm-herdr-lab.sh run "$N" workspace create --label "└ cand-$i · p:$T" --no-focus >/dev/null
  printf 'created cand-%s\n' "$i"
done

echo "== creating the ONE true candidate workspace LAST"
bin/fm-herdr-lab.sh run "$N" workspace create --label "└ stale-alive · p:$LIVETOK" --no-focus >/dev/null
echo created stale-alive

echo "== capturing workspace ids"
bin/fm-herdr-lab.sh run "$N" workspace list 2>/dev/null | jq -c '[.result.workspaces[]|{id,label}]' | tee "$EVDIR/fixture-workspaces.json"
