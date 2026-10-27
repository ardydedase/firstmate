# Live-drive evidence summary - fm/firstmate-spawn-relaunch-meta-poisoning

Change under test: base 7da4c3621370534ff9689843d2b77f34158057fb -> target 7945109a64772cdd4b790a8cf6a6653c2ee2d801
Gate worktree: /Users/adedase/.no-mistakes/worktrees/527df5d885a5/01M5XNXTTDP4G4HP70X8E6K8M0 (restored to target, clean, at teardown)

## How the drive ran (all live)

- Marked disposable lab home (`bin/fm-lab-home.sh create`), private tmux server on the
  lab's own TMUX_TMPDIR socket dir, real notes git project (seed -> bare origin -> clone),
  real treehouse worktree leases, real Claude Code 2.1.311 workers (sonnet/low, permission
  mode auto as bin/fm-live-lab.sh standardizes), trace-context on (config/trace-context +
  session-effective state). Every fm-* invocation ran from the gate worktree under the
  gate's path signal; the refusal lib permitted each call against the marked lab home
  ("fm-gate-refuse: gate agent lifecycle permitted only against lab home ...").
- Post-check oracle: `bin/fm-pr-lib.sh`'s own `fm_pr_metadata_identity_parse` (byte-identical
  between base and target; verified via git diff), plus `fm_pr_file_mode`/`fm_pr_private_file_valid`
  for the 0600 private-staging contract, and row-position facts (check-meta.sh).
- Task ids: labv1-prtail (scenario 1), labv1-heal (scenario 2), labv1-base (scenario 3).

## Scenario 1 - relaunch keeps the PR identity tail parseable (target) - PASS

- 01e-fresh-spawn.log: spawn rc=0 (41s), record 0600 with traceparent=, worker parked
  (turn-ended + "paused ... gate file" status line, 01-pane-before.txt).
- Armed the record the way fm-pr-check.sh/fm-x-lib.sh leave it: pr=, pr_head= (40 hex),
  x_request=, x_request_ts=, x_followups=, x_platform= appended as the tail
  (01-meta-armed.txt); pre-relaunch parse PASS (01-check-armed.txt).
- 01f-relaunch.log: `fm-control.sh labv1-prtail relaunch --note ...` rc=0 (41s),
  "relaunched labv1-prtail harness=claude from=claude ...".
- 01-meta-after.txt / 01-check-after.txt: replacement record has control_relaunch_tx= and
  traceparent= BEFORE the preserved tail; tail is the last block; IDENTITY-PARSE: PASS
  (url preserved); PRIVACY ok (0600). traceparent value preserved across the relaunch
  (same trace id - one task identity kept). Replacement agent ran and parked again
  ("paused [at=1793073125]" in 01f-relaunch.log; pane idle at composer, 01-pane-final.txt).

## Scenario 2 - relaunch heals a record poisoned after the tail (target) - PASS

- 02a-spawn-poison.log: worker parked; record armed, then damaged exactly as the BASE
  revision's captain-hold did (`git show 7da4c36:bin/fm-captain-hold.sh` line 1936:
  `printf 'decisions_reviewed=1\ndecision_keys=...' >> "$meta"` after the tail).
  Pre-relaunch parse FAIL (02-check-poisoned.txt).
  NOTE: this first round also seeded a 39-hex pr_head (fixture bug, mine); the relaunch
  preserved it verbatim (correct preserve semantics - preserve is not a validator).
- 02c-heal-clean.log: with the fixture repaired to a valid 40-hex pr_head, the healed
  record parses (02-check-repaired.txt); re-poisoned -> parse FAIL
  (02-check-poisoned.txt); relaunch rc=0 (54s) -> replacement record (02-meta-after.txt):
  decisions_reviewed=/decision_keys= re-slotted BEFORE the tail, pr=/pr_head=/x_* tail
  LAST, IDENTITY-PARSE: PASS, mode 0600 (02-check-after.txt). The replacement agent read
  the relaunch's operational-inbox note and stayed parked (02-pane-final.txt).
- 02b-relaunch.log is the intermediate heal round: ordering already healed there
  (control_relaunch_tx/decisions before the tail, tail last), parse FAIL only because of
  the malformed fixture pr_head it faithfully preserved.

## Scenario 3 - base-revision contrast: the defect reproduces at base - PASS (defect shown)

- 03b-base-contrast.log: worktree checked out at base 7da4c36, spawn from BASE scripts
  (24s, worker parked), record armed with valid 40-hex pr_head + tail.
- Base relaunch rc=0 (21s/35s) and "relaunched ..." - but the replacement record
  (03-meta-after.txt) ends: ... pr=, pr_head=, x_request=, x_request_ts=, x_followups=,
  x_platform=, control_relaunch_tx=, traceparent=  -> IDENTITY-PARSE: FAIL
  (03-check-after.txt). Mode -rw-r--r-- (644): the base record is not private.
- Control (03-meta-stripped-copy.txt + 03-check-control.txt): the same record with ONLY
  the relaunch-appended control_relaunch_tx/traceparent rows removed parses PASS -
  the appended rows are the sole cause of the failure.
- 03-base-contrast.log: first round of the same contrast (same conclusion; its pre-check
  also carried the 39-hex fixture pr_head plus the first relaunch's poison).
- Worktree restored to target and verified clean immediately after (both logs end with
  the target SHA).

## Additional live observations (honest, none block this change)

1. Default claude permission posture (bypass) + Claude Code 2.1.311: a fresh worker pane
   wedges on the bypass-permissions confirmation dialog (cursor on "No, exit"; firstmate
   deliberately never answers it). bin/fm-live-lab.sh's posture (config/claude-permission-mode
   = auto) avoids it; all live scenarios used auto. Pre-existing launch posture, not part
   of this change. See 01b-spawn.log + 01c-arm.log (first lab) and drive-01d.sh context.
2. fm_gate_lab_permitted requires FM_HOME to equal its physical path; a lab home addressed
   via /var/folders/... (macOS TMPDIR default) is refused until addressed via
   /private/var/... (01a-setup-spawn.log vs 01b-spawn.log).
3. WATCHER DOWN banners in spawn/relaunch logs are expected: the lab ran no primary
   session, so no watcher beacon existed; the guarded operations still ran (the banner
   says so explicitly).
4. Teardown note (04-teardown.log + the final fixup): the labs' state/<id>.git-hooks dirs
   are read-only (dr-x), so rm -rf needs chmod -R u+w first; both lab roots, all /tmp
   task-temp roots and the 6 lab claude trust entries were removed; the private tmux
   server was killed; no lab processes remain; worktree clean at target.

## File inventory

- 00-env.txt                     environment (PATH, user) used by every lab invocation
- check-meta.sh                  the post-check: product parser + privacy + row positions
- drive-01a.sh/01a-setup-spawn.log   first lab mint; gate refusal via unresolved /var path
- drive-01b.sh/01b-spawn.log     spawn with physical FM_HOME (bypass posture; worker wedged on dialog)
- drive-01c.sh/01c-arm.log       first lab pane capture + armed record check
- drive-01d.sh/01d-respawn.log   product teardown attempt across the path mismatch
- drive-01e.sh/01e-fresh-spawn.log  fresh lab (one canonical path), spawn + park + arm
- drive-01f.sh/01f-relaunch.log  SCENARIO 1 relaunch + checks
- 01-pane-before.txt / 01-pane-after.txt / 01-pane-final.txt
- 01-meta-before-seed.txt / 01-meta-armed.txt / 01-meta-after.txt
- 01-check-armed.txt / 01-check-after.txt
- drive-02a.sh/02a-spawn-poison.log  SCENARIO 2 spawn + base-shape poison (parse FAIL)
- drive-02b.sh/02b-relaunch.log   first heal round (order healed; fixture pr_head malformed)
- drive-02c.sh/02c-heal-clean.log SCENARIO 2 clean re-drive: poison -> relaunch -> heal -> PASS
- 02-pane-before.txt / 02-pane-final.txt
- 02-meta-armed.txt / 02-meta-poisoned.txt / 02-meta-after.txt
- 02-check-repaired.txt / 02-check-poisoned.txt / 02-check-after.txt
- drive-03.sh/03-base-contrast.log   SCENARIO 3 first round at base
- drive-03b.sh/03b-base-contrast.log SCENARIO 3 clean round at base (valid pr_head)
- 03-pane-before.txt
- 03-meta-armed.txt / 03-meta-after.txt / 03-meta-stripped-copy.txt
- 03-check-armed.txt / 03-check-after.txt / 03-check-control.txt
- drive-04.sh/04-teardown.log    teardown + restoration verification
- lab-state.env                  the (now removed) lab root the logs reference
