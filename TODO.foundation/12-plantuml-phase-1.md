# 12 — PlantUML phase 1: class, then sequence

Can start: after 01, 02, 04, 10, 14, 16, 17 in full, plus two PARTIAL
prerequisites its own Done criteria need:

- **19a** (the pinned CI lane skeleton) — step 3 below adds tools to a
  full lane that only item 19 creates.
- **03a** (coverage instrumentation) — "coverage floors hold" needs
  something measuring them.

The snippet runner is NOT a third prerequisite: item 16 already ships a
README-example spec of its own and blocks this item, so that harness
exists by the time we get here. This item extends it to class and
sequence; item 11 absorbs it into the all-docs harness later. Item 11 is
not a blocker.

Lint completion (09), coverage completion (03b), the docs truth pass
(11) and the corpus long tail all still run in parallel; they do not
block this.

## Scope (user-approved order)

**Class first** — expanded from the item-16 spike to full corpus-backed
support, certified before sequence implementation STARTS. Then
sequence. Separate PRs per type. (Class is the cleaner layout proof;
sequence then proves temporal semantics.)

## Do

1. PlantUML corpus: extract from plantuml's own test resources via a
   `scripts/extract_plantuml_tests.rb` (new) modeled on the mermaid
   extractor; stable case IDs from upstream path + test identity + source
   hash (item 02's rule, not ordinals); pin upstream SHA + PlantUML
   version + Java version + Graphviz version + checksums; scoreboard
   rows from day one (0% honest start).
2. **PlantUML oracle contract** — the same shape item 02 defines for
   Mermaid, written down before any verdict is generated. "The pinned
   binary renders it" is not a predicate. Specify:
   - the exact command and its arguments;
   - what counts as a valid result — PlantUML emits an SVG containing an
     error message on bad input, so exit code alone is not enough;
   - timeout value and kill behavior;
   - three distinct states: valid, rejected-by-oracle, infrastructure
     failure (missing Java, missing Graphviz, OOM) — infrastructure
     failure must never be recorded as a verdict;
   - a canary case proving the oracle is alive before a refresh is
     trusted;
   - all-or-nothing refresh: a partial run does not overwrite verdicts;
   - version and content hashes in every provenance record.

   Seed one invalid case and one infrastructure failure and prove the
   oracle classifies each correctly.
3. CI provisioning is OWNED HERE (item 19 provides the lane mechanism,
   not the tools): pinned PlantUML + Java + Graphviz added to the full
   lane by this item, before any comparison spec lands. Comparison
   specs FAIL (not skip) in CI when a reference binary is missing; loud
   skip only in local dev.
4. Class: grow the spike's grammar to the corpus, bucket-by-bucket like
   item 06. Then sequence from scratch through the same gates.
5. Per type, all five issue-#2 criteria: corpus at 100% of oracle-valid;
   svg_conform valid; item-14 parity gate vs the PlantUML binary; specs
   incl. edge cases (coverage floors hold); runnable README example
   (snippet-spec-executed).

## Phase close-out

- **Phase-end 0.x release** (owned here; item 17 owns only the two
  pre-12 cuts): the release that announces PlantUML support.
- `TODO.notations` roadmap (DOT, D2, BPMN, Structurizr, BlockDiag
  family, Priority 2/3 — with the typed-IR phase, item 18, as its
  first entry, designed from Mermaid + PlantUML evidence) merged via a
  PR whose body records each chain gate's verdict. The foundation is
  not complete without this roadmap.

## Files

`lib/sirena/notation/plantuml/**`, `spec/plantuml/`,
`scripts/extract_plantuml_tests.rb` (new), CI workflows.
