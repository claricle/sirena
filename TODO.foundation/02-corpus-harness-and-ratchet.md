# 02 — Corpus oracle, provenance, and the scoreboard

Split into two PRs. **02a** pins the oracle toolchain; **02b** builds the
harness, the scoreboard and the ratchet. 02b's verdict generation cannot
start before 02a lands — an unpinned renderer produces verdicts nobody
can reproduce.

Can start: now — 02a immediately, 02b's design in parallel with its
verdict generation waiting on 02a. Only 02a's CI wiring waits for 19a's
lane. Blocks: 03, 05, 06, 07, 14, and the completion of 04, 09, 10. Caveat: the in-bundle gates ("`bundle exec
rake` runs the corpus") need a loading gem — that's item 01; until it
lands, the uncommitted 0.7-pin workaround applies.

## Problem

Nothing in default rake or CI runs and ratchets the 1,997-case corpus
(`scripts/corpus_sweep.rb` is manual-only), so 30.7% (614/1997) is
unprotected.

The oracle is not actually pinned. "mmdc 11.12.0" pins only the CLI
wrapper: its `package.json` requires `mermaid ^11.0.2`, and the current
install resolves mermaid 11.16.1 with Puppeteer 23.11.1. The repo has no
`package.json`, no lockfile, no browser pin and no container, and
`lib/tasks/generate_mermaid_fixtures.rake:14` shells out to whatever
`mmdc` is on PATH. Two machines can disagree about what is oracle-valid.

Case identity is unstable. `scripts/extract_mermaid_tests.rb:445` names
each case by its per-type ordinal, so one upstream insertion renames
every later case — the per-case ratchet then reads as mass deletion plus
mass creation. The script also hardcodes an absent checkout, records no
upstream SHA, and writes into an existing tree it never cleans. That
tree carries 11 duplicate basenames across 23 files and 365
duplicate-content groups covering 1,137 files, plus 302 `.svg` and 330
machine-specific `.error` files the script cannot reproduce.

Structural debt on top of that: duplicate type dirs (class/class_diagram,
er/er_diagram, state/state_diagram, git/gitgraph), an 85-case `unknown/`
dir, and `spec/fixtures_mermaid/` holding ~847 unique reference SVGs
duplicated into `correct/` subdirs (not 1,694) with no provenance file
for any of them.

## Do — 02a, hermetic oracle toolchain

1. Commit an exact Node dependency tree (`package.json` +
   `package-lock.json`) or an immutable container digest covering Node,
   `@mermaid-js/mermaid-cli`, `mermaid`, Puppeteer, the Chromium build
   and the font set. Record every one of those versions in the oracle
   provenance record.
2. Make the fixture and oracle tasks invoke the pinned toolchain, never
   ambient `mmdc`.
3. Add a drift check: if the resolved toolchain differs from the
   recorded provenance, the run fails rather than producing verdicts.

02a does NOT regenerate references. The generator and comparator join
references to inputs by basename
(`lib/tasks/generate_mermaid_fixtures.rake:133`), and 02b is about to
rename every case — references generated first would go stale the
moment stable IDs land. Reference regeneration happens in 02b, after
the rename, under this pin.

## Do — 02b, harness, scoreboard, ratchet

1. **Oracle**: a case is *valid* iff the 02a-pinned toolchain renders it
   — exit 0, parseable non-error SVG, no timeout. Verdicts recorded per
   case with the full 02a provenance; refreshed only via a reviewed
   toolchain bump. Oracle-invalid cases stay in the corpus, leave every
   target.
2. **Scoreboard** (`scoreboard/` at repo root): the ONE ratchet
   mechanism for the whole plan. **Per-case rows, never aggregate
   counts** — corpus status, conformance status (item 04), parity status
   (item 14). Aggregate numbers are derived from rows, so fixing case A
   while breaking case B still fails. Metric columns other items
   register (lint debt, coverage floors) sit alongside. One CI guard
   diffs against the merge-base copy: any regression fails; any
   unrecorded improvement fails as stale. Expected `unsupported` exists
   ONLY as oracle-invalid — no judgment statuses.
3. Corpus spec: render every case and record **structured `stage` and
   `error_class`** per case, not just pass/fail. `DiagramTypeError` from
   `Engine` must be distinguishable as `detect-fail` — item 05's failure
   list is derived from that field, and `engine.rb:101` already keeps
   that exception separate from later pipeline failures. Wire into
   default rake + CI.
4. **Stable case identity.** Derive case IDs from canonical upstream
   path + test identity + source hash, never from ordinal position.
   Ship an old→new migration manifest for the one-time rename. Collisions
   are a hard failure, not a silent overwrite. Upstream-removed cases are
   retained unless the oracle rejects them; unexplained deletion is a
   regression.
5. **Reproducible extraction.** Take the mermaid-js checkout path and
   commit SHA as parameters, write the SHA into every `.meta.json`,
   regenerate into an empty temporary root and swap, and either delete
   the `.svg`/`.error` sidecars or regenerate them reproducibly. Assert
   case counts and the provenance multiset before the recursive diff, so
   a lossy regeneration cannot pass by accident.
6. Normalize duplicate dirs; document `.meta.json`; publish one
   canonical type-name table shared with the rake task and the registry.
   **Item 10 relocates that registry — the table's location is settled
   with item 10 before either lands.**
7. Dedupe `spec/fixtures_mermaid/` (`correct/` copies), then regenerate
   it under 02a's pinned toolchain — AFTER step 4's rename, so
   references key off stable IDs rather than the old ordinals. Store per
   reference: source hash, upstream SHA, renderer/browser versions, the
   exact command, and an output checksum. Regeneration must produce zero
   diff. These references feed item 14's comparator, so a reference
   exists for **every oracle-valid case**, not just the 847 that happen
   to have one today.
8. Interim: tighten `fixtures_spec.rb`'s 0.02–2.0 length band (50x
   smaller currently passes) until 14's comparator retires it.
9. `scripts/corpus_sweep.rb` is the committed instrument behind every
   corpus pass-rate figure in this plan (the 30.7% and all the per-type
   numbers), and it has no specs of its own. Cover it: classification
   correctness on seeded pass/parse-fail/render-fail/timeout inputs, and
   the `--failing` output shape. An unverified instrument makes those
   measurements unverified.

## Done when

**02a**

- The toolchain manifest/lockfile (or container digest) is committed and
  every oracle/fixture path uses it.
- A seeded drift (bumped mermaid or browser version) makes the run fail.
- `spec/fixtures_mermaid/` regeneration under the pin produces zero diff,
  and every reference carries its provenance record.

**02b**

- `bundle exec rake` runs the corpus against the scoreboard.
- Scoreboard guard: a guard spec seeds one regression and one
  unrecorded improvement; both seeded runs exit non-zero.
- A seeded `DiagramTypeError` case lands in the scoreboard as
  `detect-fail`, proving item 05's input exists.
- Zero cases without an oracle verdict and provenance — including
  `unknown/` (fixing or reclassifying those cases is item 05's job;
  this item only guarantees every one carries a verdict).
- Corpus refresh reproducible: the extraction script re-run against a
  mermaid-js checkout at the pinned SHA regenerates `spec/mermaid/`
  with zero git diff, and counts + provenance multiset match.
- Identity holds under an inserted upstream test, a reordered upstream
  test and an upstream deletion — proven by three seeded cases, not by
  argument.
- The post-scoreboard sweep confirms the pre-scoreboard rehearsal
  deltas (radar 13→14, treemap 0→9) or records why they moved.

## Files

`package.json` + `package-lock.json` (new, 02a),
`spec/mermaid_corpus_spec.rb` (new), `scoreboard/` (new),
`spec/mermaid/README.md` (new),
`scripts/extract_mermaid_tests.rb`, `lib/tasks/generate_mermaid_fixtures.rake`,
CI workflow.
