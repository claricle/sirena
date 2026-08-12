# 14 — elkrb integration + layout parity

Comparator DESIGN can start after 02b's reference regeneration (step 7)
— the design needs to know what a reference looks like, and the
references are being rebuilt. INTEGRATION and Done need **both 01 and
02**: step 1 proves elkrb works functionally under lutaml-model 0.8, and
that cannot run while the gem still crashes at require. Completion also
needs 03a, and raises the branch floor 80 → 90 jointly with item 07.
Blocks: 12; with item 04, blocks 16's completion.

## Facts

`Engine#layout_graph` never calls elkrb — fallback grid with a TODO
(`lib/sirena/engine.rb:178-181`) — while README.adoc, ARCHITECTURE.md,
and parts of `docs/` still claim ELK layout.
elkrb 1.0.2 resolves and requires cleanly under lutaml-model 0.8
(proven 2026-08-11), but its FUNCTIONAL behavior under 0.8 is
untested — step 1 must prove it before anything builds on it.
References for parity: the deduped `spec/fixtures_mermaid/` set
(~847 unique SVGs; item 02 dedupes). Transforms emit heterogeneous
shapes — flowchart is ELK-ish, block/quadrant are pre-positioned — so
"elkrb for all types" is per-type work, not one engine edit.

## Bars (user-ruled)

- Structural invariants: **hard gate** — all nodes present, all edges
  connecting the right nodes, no PEER overlaps, labels attached to
  owners. ("No overlaps" unqualified would reject correct output;
  ancestor containment is legitimate — see the metric contract below.)
- Geometry: per-case scoreboard ratchet; **8% node-center / 15%
  dimension-aspect are the targets**. Renegotiation happens **per type
  only** (never per case — case-level waivers would hollow the target):
  measured evidence that algorithm identity, not our code, makes the
  number unreachable; the user decides. Bars raise later once stable.

## Metric contract (settle before the comparator is written)

The bars above are unmeasurable as stated. The contract must define,
IN THIS FILE and not in an untracked options doc:

- **Node identity** — how a Sirena node is matched to a reference node
  (semantic id, not document order).
- **Normalization** — the denominator is the reference diagram's
  diagonal; state how scale and translation are removed, and how nested
  `transform` attributes are flattened before comparison.
- **The equations** — node-center distance and dimension/aspect
  deviation, written out, plus whether the threshold is per node or
  aggregated (and if aggregated, by what statistic).
- **Overlap semantics.** "No overlaps" as written rejects correct
  output. `Transform::Treemap` (`treemap.rb:70`) and
  `Transform::BlockTransform` (`block.rb:100`) deliberately nest
  children inside parent bounds. Ancestor containment is ALLOWED; peer
  collision is a failure.
- **Non-box types.** `Transform::PieTransform` (`pie.rb:17`) emits no
  node boxes at all. Each such type gets either an analogous metric
  (e.g. sector angle and radius deviation) or an explicit,
  user-approved N/A — never a silently vacuous pass.
- **Failure evidence format** — what a failing case records so the next
  session can act on it.

## Reference cohort (scoping the hard gate)

Two different gaps, and conflating them is how "all reference cases"
became meaningless:

- **Not every corpus case has a reference.** There are 1,997 corpus
  inputs and only ~847 references. mmdc renders cases that have no
  reference at all (`class_diagram/001_platform_click_security_loose_0.mmd`
  is one), and the comparator silently skips a missing reference
  (`generate_mermaid_fixtures.rake:276`). So corpus completion does NOT
  produce references — reference GENERATION does. That is item 02b step
  7, which regenerates a reference for every oracle-valid case under the
  02a pin. `spec/fixtures_mermaid/` also has 23 type dirs and no sankey
  directory despite sankey being registered; the same step fixes that,
  or records an oracle-backed N/A.
- **Not every case Sirena can render.** At most today's 614 pass cases
  produce candidate output to compare.

So the critical-path cohort is **oracle-valid ∩ has-a-reference ∩
currently Sirena-pass**. Every newly-passing corpus PR (items 05/06/07)
adds or updates its own parity row, so the cohort grows with the pass
set instead of gating on it. Global closure needs BOTH 02b's reference
generation and the corpus tracks — and a skipped missing reference must
fail rather than pass silently.

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

- Every type whose layout elkrb can meaningfully own is on elkrb. Some
  cannot be: pie has no node boxes, and block/quadrant are
  pre-positioned by construction. Each such type carries a recorded,
  user-approved exception with its evidence — the point is that no type
  is left undecided, not that elkrb runs everywhere.
- **Zero invariant failures across the cohort** (oracle-valid ∩
  has-a-reference ∩ Sirena-pass) — the hard gate, stated as the
  completion bar, not just a mechanism. Cohort membership is read from
  the scoreboard, never hardcoded.
- A reference-completeness assertion passes: every oracle-valid case has
  a reference or an explicit oracle-backed N/A row, and every registered
  type has at least one (sankey has none today). A missing reference
  FAILS the comparator instead of being skipped.
- Every type's geometry at 8%/15% OR at its user-approved renegotiated
  per-type threshold — no third state. Non-box types meet their
  analogous metric or carry an approved N/A.
- The branch floor is raised 80 → 90 by whichever of this item and item
  07 lands second — an acceptance criterion here, not a side effect.
- Comparator in CI (full lane). Every ELK mention across `README*`,
  `ARCHITECTURE.md`, `docs/` and `sirena.gemspec` has a row
  in item 11's committed manifest resolved as verified / corrected /
  removed. Grep finds the mentions; the manifest decides which are true,
  because after this item lands some ELK claims become correct. The
  gemspec description still claims
  ELK layout; it counts.

## Files

`lib/sirena/engine.rb`, `lib/sirena/transform/*`,
`spec/layout_parity_spec.rb` + comparator lib, scoreboard.
