# Test-phase validation: fm/firstmate-spawn-relaunch-meta-poisoning
base af1c6817fc47589b162cbc361671c43cdb150933 → target cc138a034236fb0473bc8db5081e28a37ef6fb82

## What was validated live
A real firstmate live lab (fm-live-lab-style) was brought up on the TARGET commit:
the lab home was a genuine primary checkout of cc138a03 at /private/tmp/fmlab.LydRD5,
a real ship worker (labd0daf92a317c-worker) was spawned through bin/fm-spawn.sh
(target code) with a real Claude Code agent that parked idle, and a real Claude Code
primary (first mate) drove both relaunch cycles conversationally through
bin/fm-control.sh. All record/content assertions below were re-printed from the live
files at the time of each capture. Teardown used bin/fm-live-lab.sh down with no
residue (no tmux/claude processes, no ~/.treehouse change, clean worktree).

## Evidence files
- live-lab-provisioning-and-primary-transcript.txt — up log, lab record, target
  checkout sha, readiness probe (LABREADY-d0daf92a317c), and the primary's exact
  transcript for both relaunch drives (both EXIT_STATUS=0, stdout "relaunched
  labd0daf92a317c-worker harness=claude from=claude ... endpoint=firstmate:...").
- scenario1-armed-meta.txt — live record after arming the PR identity tail
  (pr=/pr_head= at EOF, mode 0600) and target fm_pr_metadata_identity_parse PARSE_OK.
- scenario1-post-relaunch.txt — live record after relaunch #1: control_relaunch_tx=
  landed at row 16 BEFORE the tail; pr=/pr_head= remained the last two rows; mode
  0600; parse PARSE_OK with the same github identity; new busy/spawn generations;
  replacement claude alive; control receipt phase=complete.
- scenario2-poisoned-meta.txt — adversarial post-tail append (decisions_reviewed=,
  decision_keys=, a duplicated control_relaunch_tx=) on the LIVE record; parse
  REJECTED by both target and base af1c6817 parsers; base..target diff shows the
  parser itself is unchanged (the fix is in the writers).
- scenario2-post-heal.txt — live record after relaunch #2: parse PARSE_OK again,
  pr=/pr_head= restored as the final rows, the two poison rows preserved exactly
  once each and repositioned before the tail, exactly one control_relaunch_tx= row
  (stale duplicate dropped), mode 0600, control receipt phase=complete, replacement
  claude alive.
- hermetic-fm-control-relaunch-suite.log — full targeted hermetic suite log
  (tests/fm-control-relaunch.test.sh): 91 ok, 0 not ok, EXIT=0.
- live-lab-up.log — raw fm-live-lab.sh up output (worker spawned live; a benign
  bookkeeping race aborted the driver before its primary-launch step, so the
  primary was launched and driven manually with the same canonical argv/env).
