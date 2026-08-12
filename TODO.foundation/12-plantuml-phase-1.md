# 12 — PlantUML phase 1: class, then sequence

Can start: after 01, 02, 04, 10, 14, 16, 17 — and ONLY those.
Lint completion (09), coverage completion (03), docs truth (11), and
the corpus long tail run in parallel; they do not block this.

## Scope (user-approved order)

**Class first** — expanded from the item-16 spike to full corpus-backed
support, certified before sequence implementation STARTS. Then
sequence. Separate PRs per type. (Class is the cleaner layout proof;
sequence then proves temporal semantics.)

## Do

1. PlantUML corpus: extract from plantuml's own test resources; pin
   upstream source + PlantUML version + checksums; oracle = the pinned
   PlantUML binary renders it; scoreboard rows from day one (0% honest
   start).
2. CI provisioning is OWNED HERE (item 19 provides the lane mechanism,
   not the tools): pinned PlantUML + Java + Graphviz added to the full
   lane by this item, before any comparison spec lands. Comparison
   specs FAIL (not skip) in CI when a reference binary is missing; loud
   skip only in local dev.
3. Class: grow the spike's grammar to the corpus, bucket-by-bucket like
   item 06. Then sequence from scratch through the same gates.
4. Per type, all five issue-#2 criteria: corpus at 100% of oracle-valid;
   svg_conform valid; item-14 parity gate vs the PlantUML binary; specs
   incl. edge cases (coverage floors hold); runnable README example
   (snippet-spec-executed).

## Phase close-out

- **Phase-end 0.x release** (owned here; item 17 owns only the two
  pre-12 cuts): the release that announces PlantUML support.
- `TODO.notations` roadmap written and review-chain-approved: DOT, D2,
  BPMN, Structurizr, BlockDiag family, Priority 2/3 — with the typed-IR
  phase (item 18) as its first entry, designed from Mermaid + PlantUML
  evidence. The foundation is not complete without this roadmap.

## Files

`lib/sirena/notation/plantuml/**`, `spec/plantuml/`, CI workflows.
