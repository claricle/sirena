# 02 — Corpus oracle, provenance, and the scoreboard

Can start: now (oracle + scoreboard don't need 01). Blocks: 03, 05, 06, 07, 14.

## Problem

Nothing runs the 1,997-case corpus, so 30.2% is invisible and
unprotected. The corpus also has structural debt: duplicate type dirs
(class/class_diagram, er/er_diagram, state/state_diagram, git/gitgraph),
an 85-case `unknown/` dir, ~330 `.error`-marked cases inflating
denominators, an extraction script hardcoding another user's path with
no upstream commit pinned, and `spec/fixtures_mermaid/` holding ~847
unique reference SVGs duplicated into `correct/` subdirs (not 1,694).

## Do

1. **Oracle**: a case is *valid* iff pinned mmdc 11.12.0 renders it —
   exit 0, parseable non-error SVG, no timeout. Verdicts recorded per
   case with provenance; refreshed only via a reviewed mmdc bump.
   Oracle-invalid cases stay in the corpus, leave every target.
2. **Scoreboard** (`scoreboard/` at repo root): the ONE ratchet
   mechanism for the whole plan. Per-case corpus status, plus metric
   columns other items register (conformance counts, lint debt,
   coverage floors, parity). One CI guard diffs against the merge-base
   copy: any regression fails; any unrecorded improvement fails as
   stale. Expected `unsupported` exists ONLY as oracle-invalid — no
   judgment statuses.
3. Corpus spec: render every case, classify pass/parse-fail/render-fail/
   timeout, compare to scoreboard. Wire into default rake + CI.
4. Normalize duplicate dirs; document `.meta.json`; make extraction
   reproducible (mermaid-js path+commit as parameters, SHA into meta,
   one canonical type-name table shared with the rake task and registry).
5. Dedupe `spec/fixtures_mermaid/` (`correct/` copies) and record the
   real count; these references feed item 14's comparator.
6. Interim: tighten `fixtures_spec.rb`'s 0.02–2.0 length band (50x
   smaller currently passes) until 14's comparator retires it.

## Done when

- `bundle exec rake` runs the corpus against the scoreboard.
- Scoreboard guard proves both directions (regression + stale) in CI.
- Zero cases without an oracle verdict and provenance — including
  `unknown/` (fixing or reclassifying those cases is item 05's job;
  this item only guarantees every one carries a verdict).
- Corpus refresh is reproducible by anyone from a mermaid-js checkout.

## Files

`spec/mermaid_corpus_spec.rb`, `scoreboard/`, `spec/mermaid/README.md`,
`scripts/extract_mermaid_tests.rb`, `lib/tasks/generate_mermaid_fixtures.rake`,
CI workflow.
