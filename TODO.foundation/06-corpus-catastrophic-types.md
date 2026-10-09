# 06 — Corpus burndown: flowchart, state, er, treemap

Status (reconciled 2026-10-10): **complete.** Across flowchart, state,
state_diagram, er, er_diagram and treemap, `scoreboard/corpus.json` records
293 oracle-valid cases and all 293 pass. The other 443 rows are classified as
415 extraction artifacts and 28 pinned-oracle rejections; none has an unknown
verdict. The enforced branch floor is already 89% in `.simplecov`, stronger
than this item's 70% acceptance floor.

Can start: after 02. Completion also needs 03a (changed-line gate) and
raises the branch floor 55 → 70.

**Parallelism is conditional, not free.** `Flowchart`, `StateDiagram`
and `ErDiagram` all subclass `Grammars::Common` — a fix in a shared rule
changes every type at once. So:

- Type-local edits (a type's own grammar/transform/renderer): parallel.
- Anything touching `grammars/common.rb`: serialized on a single
  shared-grammar track, one change at a time, verified with a FULL
  corpus sweep across all types, not just the owning type.

A sub-track that discovers its bucket needs a common-rule change hands
that piece to the shared track instead of editing in parallel.

## Target (user-ruled)

**100% of oracle-valid cases, per type.** A case leaves the denominator
only if pinned mmdc itself rejects it. No judgment allowlist. The
scoreboard locks every gain.

## Sub-tracks (parallel; sizes are raw pre-oracle counts)

| Sub-todo | Cases | Today | Notes |
|---|---|---|---|
| 06a flowchart | 331 | 6.0% | largest individual corpus directory by failures (311); item 07a's class + class_diagram pair totals 341 |
| 06b state (+state_diagram) | 234 | ~4% | composite states, concurrency |
| 06c er (+er_diagram) | 161 | ~3% | attribute blocks, label variants |
| 06d treemap | 10 | 90% (9/10) | wiring fixed in rehearsal (commit 7722ee1's renderer return contract — measured 9/10); one case remains, and the triage note recorded it as a likely oracle rejection, which item 02's verdict settles |

Item 06 owns 736 cases. Item 07's table carries the reconciliation
against the full 1,997.

## Method (each sub-track)

1. Classify failures into buckets by **root construct**, found by
   bisecting the input — the method the `sirena-corpus` skill defines.
   A parslet failure location names where the parse gave up, which is
   often not where the unsupported construct is. Buckets are facts;
   hypotheses go in the bucket doc.
2. Fix buckets largest-first: grammar → transform → renderer. One
   bucket per PR, corpus cases as specs, scoreboard updated.
3. Never hand-patch one case; a fix clears its bucket or explains the
   remainder.
4. Branch-coverage tests ride along (item 03's timeline).

## Done when

Complete. Each owned type is at 100% of oracle-valid (293/293 in aggregate),
and every non-pass is classified as an extraction artifact or pinned-oracle
rejection. The current 89% branch floor exceeds the required 70% floor.

This is a reconciliation after the implementation and coverage work landed,
not a claim that the historical PR sequence followed the plan's proposed
55 → 70 choreography. The repository moved through stronger accumulated
coverage floors before this plan card was closed; this closeout records the
current enforced result and neither replays nor lowers a floor.

The 70 → 80 raise is shared with item 07's 07a–07c sub-tracks and
follows the same second-finisher rule: if this item closes FIRST it
records the handoff in its PR body; if it closes SECOND it performs the
raise. That historical handoff is now superseded by the enforced 89% floor;
item 07 still carries its separate 90% joint handoff with item 14.

## Files

`lib/sirena/parser/{grammars,transforms}/{flowchart,state_diagram,er_diagram,treemap}.rb`
and their parser/transform/renderer counterparts; specs per bucket.
