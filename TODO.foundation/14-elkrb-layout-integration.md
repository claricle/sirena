# 14 — elkrb integration + layout parity

Can start: after 02 (comparator needs references). Blocks: 12.

## Facts

`Engine#layout_graph` never calls elkrb — fallback grid with a TODO
(`lib/sirena/engine.rb:~181`) — while all docs claim ELK layout.
References for parity: the deduped `spec/fixtures_mermaid/` set
(~847 unique SVGs; item 02 dedupes). Transforms emit heterogeneous
shapes — flowchart is ELK-ish, block/quadrant are pre-positioned — so
"elkrb for all types" is per-type work, not one engine edit.

## Bars (user-ruled)

- Structural invariants: **hard gate** — all nodes present, all edges
  connecting the right nodes, no overlaps, labels attached to owners.
- Geometry: per-case scoreboard ratchet; **8% node-center / 15%
  dimension-aspect are the targets**. Renegotiation happens **per type
  only** (never per case — case-level waivers would hollow the target):
  measured evidence that algorithm identity, not our code, makes the
  number unreachable; the user decides. Bars raise later once stable.

## Do

1. Prove elkrb on ONE type first (flowchart — already ELK-shaped),
   behind the invariants + ratchet. Explicit failure if elkrb errors —
   no silent fallback; decide whether the grid survives as opt-in.
2. Verify what each transform emits vs what elkrb accepts against the
   REAL gem (dependency-contract-check), then roll out per type.
3. Comparator: invariants + normalized geometry vs references; baseline
   fallback first (honest start), then elkrb; scoreboard per case.
4. After each type flips, refresh every doc statement about its layout
   (owned here, not hoped from item 11).

## Done when

- All types on elkrb (or user-decided per-type exceptions with evidence).
- **Zero invariant failures across all reference cases** (the hard gate,
  stated as the completion bar, not just a mechanism).
- Every type's geometry at 8%/15% OR at its user-approved renegotiated
  per-type threshold — no third state.
- Comparator in CI (full lane); zero stale layout claims anywhere.

## Files

`lib/sirena/engine.rb`, `lib/sirena/transform/*`,
`spec/layout_parity_spec.rb` + comparator lib, scoreboard.
