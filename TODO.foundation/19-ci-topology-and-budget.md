# 19 — CI topology, runtime budget, external pins

Can start: now. Owns what no other item did: CI as a system.

## Problem

- `rake.yml` and `release.yml` delegate to metanorma/ci reusable
  workflows at `@main` — mutable external code deciding our gates
  (same hole as the unpinned rubocop config, bigger blast radius).
- The plan adds per-push: corpus sweep, coverage suite, conformance
  spec, parity comparator, two rubocop runs, fresh-resolution install,
  docs build. Nobody owns total wall-time or job topology — gate-heavy
  plans without a budget end with gates quietly demoted.
- The mermaid reference binary (mmdc) exists only on the maintainer's
  machine. (PlantUML/Java/Graphviz provisioning is item 12's problem,
  not this item's.)

## Do

1. Pin metanorma/ci workflow references to a SHA; document the bump
   procedure. Read what generic-rake actually runs; make our gates
   explicit rather than inherited-by-surprise.
2. Job topology + budget: TWO lanes, BOTH required before merge —
   nothing gate-shaped runs only after merge (a regression outside a
   "slice" must never land first and get caught on main).
   - Fast lane: unit suite, lint, scoreboard guard, snippet spec —
     budget < 10 min, feedback while you work.
   - Full lane: whole corpus, parity, conformance, fresh-resolution
     install, docs build — budget < 30 min, parallelized jobs; a
     required PR check, merge waits for it.
   Nightly re-runs the full lane on main as a belt-and-braces check,
   not as the primary gate. Budgets recorded here; a new gate must fit
   the budget or extend it explicitly in review.
3. Provision pinned mmdc 11.12.0 in the full lane (item 12 owns the
   PlantUML/Java/Graphviz toolchain when its lane work starts).
   Oracle/comparison specs FAIL when a binary is missing in CI;
   loud-skip only locally.
4. Scoreboard guard runs in BOTH lanes (cheap, reads files).

## Done when

All external CI references pinned; both lanes live within budget;
pinned mmdc provisioned in the full lane; no gate outside a lane.
