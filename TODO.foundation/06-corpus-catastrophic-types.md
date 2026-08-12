# 06 — Corpus burndown: flowchart, state, er, treemap

Can start: after 02. Each sub-track is independently dispatchable to a
parallel agent (different grammar files — no merge conflicts).

## Target (user-ruled)

**100% of oracle-valid cases, per type.** A case leaves the denominator
only if pinned mmdc itself rejects it. No judgment allowlist. The
scoreboard locks every gain.

## Sub-tracks (parallel; sizes are raw pre-oracle counts)

| Sub-todo | Cases | Today | Notes |
|---|---|---|---|
| 06a flowchart | 331 | 6.0% | biggest single lever in the repo |
| 06b state (+state_diagram) | 234 | ~4% | composite states, concurrency |
| 06c er (+er_diagram) | 161 | ~3% | attribute blocks, label variants |
| 06d treemap | 10 | 0% | 0% smells like wiring, check registration first |

## Method (each sub-track)

1. Classify failures into buckets by parslet failure location — buckets
   are facts, hypotheses go in the bucket doc.
2. Fix buckets largest-first: grammar → transform → renderer. One
   bucket per PR, corpus cases as specs, scoreboard updated.
3. Never hand-patch one case; a fix clears its bucket or explains the
   remainder.
4. Branch-coverage tests ride along (item 03's timeline).

## Done when

Each type at 100% of oracle-valid; zero unexplained failures.

## Files

`lib/sirena/parser/{grammars,transforms}/{flowchart,state_diagram,er_diagram,treemap}.rb`
and their parser/transform/renderer counterparts; specs per bucket.
