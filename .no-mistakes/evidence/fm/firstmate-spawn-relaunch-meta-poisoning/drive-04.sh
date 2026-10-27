#!/usr/bin/env bash
# Live drive, phase 4: teardown in the same evidence turn.
#  - kill the lab's private tmux server (takes the three claude workers down)
#  - verify no process still references a lab path
#  - remove both lab roots (chmod the read-only git-hooks dirs first) and the
#    /tmp task-temp roots
#  - remove this lab's claude trust entries from ~/.claude.json (atomic,
#    same pattern as bin/fm-live-lab.sh down)
#  - verify the gate worktree is clean at the target commit
set -u
EV=/Users/adedase/.no-mistakes/evidence/01M5XNXTTDP4G4HP70X8E6K8M0
ROOT=/Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0
TARGET=7945109a64772cdd4b790a8cf6a6653c2ee2d801
LOG="$EV/04-teardown.log"
exec >"$LOG" 2>&1
PATHV=$(sed -n 's/^PATH=//p' "$EV/00-env.txt")
. "$EV/lab-state.env"

echo "### lab server windows before teardown"
env -i HOME="$HOME" PATH="$PATHV" TERM=xterm-256color TMUX_TMPDIR="$LAB/tmux" \
  tmux list-windows -t firstmate -F '#{window_name} #{pane_current_command}' 2>/dev/null || echo "(no server)"

echo "### kill the lab's private tmux server"
env -i HOME="$HOME" PATH="$PATHV" TERM=xterm-256color TMUX_TMPDIR="$LAB/tmux" \
  tmux kill-server 2>/dev/null && echo "kill-server sent" || echo "kill-server rc=$? (already gone?)"
sleep 3

echo "### residual processes referencing a lab path (expect none)"
ps -axo pid,command | grep -F "fm-lab." | grep -v grep || echo "none"

OLDLAB=/private/var/folders/rz/f8b2_npd0tjf2624px5jw_980000gn/T/fm-lab.d7A00V
echo "### remove lab roots: $LAB and $OLDLAB"
chmod -R u+w "$OLDLAB" 2>/dev/null
rm -rf "$OLDLAB" && echo "old lab removed" || echo "old lab rm rc=$?"
rm -rf "$LAB" && echo "lab removed" || echo "lab rm rc=$?"
ls -d "$LAB" "$OLDLAB" 2>/dev/null || echo "both lab roots gone"

echo "### remove /tmp task-temp roots"
ls -d /tmp/fm-labv1-* 2>/dev/null || echo "(none)"
rm -rf /tmp/fm-labv1-prtail /tmp/fm-labv1-heal /tmp/fm-labv1-base
ls -d /tmp/fm-labv1-* 2>/dev/null || echo "task temp roots gone"

echo "### remove the labs' claude trust entries from ~/.claude.json"
node - "$HOME/.claude.json" "$LAB" "${LAB#/private}" "$OLDLAB" "${OLDLAB#/private}" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const [link, ...roots] = process.argv.slice(2);
const store = fs.realpathSync(link);
const stat = fs.statSync(store);
if (!stat.isFile() || stat.uid !== process.getuid()) {
  console.error(`error: ${store} is not a regular file this user owns`); process.exit(1);
}
const inLab = (key) => roots.some((r) => r && (key === r || key.startsWith(`${r}/`)));
const fingerprint = (buf) => crypto.createHash("sha256").update(buf).digest("hex");
for (let attempt = 0; attempt < 3; attempt += 1) {
  const original = fs.readFileSync(store);
  const root = JSON.parse(original.toString("utf8"));
  const projects = root.projects;
  if (projects === undefined) { console.log(0); process.exit(0); }
  if (projects === null || typeof projects !== "object" || Array.isArray(projects)) {
    console.error(`error: ${store} has a non-object "projects" value`); process.exit(1);
  }
  const removed = Object.keys(projects).filter(inLab);
  if (removed.length === 0) { console.log(0); process.exit(0); }
  const kept = Object.keys(projects).filter((k) => !inLab(k));
  for (const key of removed) delete projects[key];
  const tmp = path.join(path.dirname(store), `.claude.json.fm-live-lab.${process.pid}.${crypto.randomBytes(8).toString("hex")}`);
  fs.writeFileSync(tmp, `${JSON.stringify(root, null, 2)}\n`, { mode: fs.statSync(store).mode & 0o777, flag: "wx" });
  let renamed = false;
  try {
    if (fingerprint(fs.readFileSync(store)) !== fingerprint(original)) continue;
    fs.renameSync(tmp, store);
    renamed = true;
  } finally {
    if (!renamed) fs.rmSync(tmp, { force: true });
  }
  const back = Object.keys(JSON.parse(fs.readFileSync(store, "utf8")).projects || {});
  if (back.some(inLab) || kept.some((k) => !back.includes(k))) {
    console.error(`error: ${store} did not keep exactly the non-lab entries`); process.exit(1);
  }
  console.log(removed.length);
  process.exit(0);
}
console.error(`error: ${store} kept changing while lab entries were being removed`);
process.exit(1);
NODE
echo "trust-entry removal rc=$?"

echo "### worktree final state (must be target, clean)"
cd "$ROOT" || exit 1
git rev-parse HEAD
git status --porcelain | head -5
[ -z "$(git status --porcelain)" ] && echo "worktree clean" || echo "WORKTREE DIRTY"
[ "$(git rev-parse HEAD)" = "$TARGET" ] && echo "HEAD at target" || echo "HEAD NOT AT TARGET"
echo "### OK phase 4 complete"
