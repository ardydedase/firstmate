#!/usr/bin/env bash
# Live-drive post-check: runs firstmate's OWN identity-parse contract against a
# live task record, then reports the ordering facts the relaunch poisoning fix
# is about. Usage: check-meta.sh <meta-file> <state-dir> <label>
set -u
ROOT="/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0"
# shellcheck disable=SC1091
. "$ROOT/bin/fm-pr-lib.sh"
meta=$1 state=$2 label=$3
echo "=== $label ==="
echo "meta: $meta"
[ -f "$meta" ] || { echo "MISSING: $meta"; exit 1; }
if fm_pr_metadata_identity_parse "$meta"; then
  echo "IDENTITY-PARSE: PASS url=${FM_PR_META_URL:-} provider=${FM_PR_META_PROVIDER:-}"
else
  echo "IDENTITY-PARSE: FAIL (fm_pr_metadata_identity_parse exit $?)"
fi
mode=$(fm_pr_file_mode "$meta")
device=$(fm_pr_file_device "$state" 2>/dev/null) || device=missing
if fm_pr_private_file_valid "$meta" 600 "$device"; then
  echo "PRIVACY: ok (mode $mode on state device)"
else
  echo "PRIVACY: BAD (mode $mode device ${device:-none})"
fi
echo "--- key row positions (line numbers) ---"
grep -n '^pr=\|^pr_head=\|^x_request=\|^control_relaunch_tx=\|^traceparent=\|^decisions_reviewed=\|^decision_keys=' "$meta" || echo "(none)"
echo "--- last 6 rows ---"
tail -n 6 "$meta"
