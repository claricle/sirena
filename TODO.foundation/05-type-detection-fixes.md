# 05 — Diagram type detection fixes

Can start: after 02 (needs the failure list). Completion also needs 03a
— this item changes behavior, so its PRs need the changed-line gate.
Small; unblocks corpus cases across many types.

## Facts

104 corpus failures are `DiagramTypeError` — 71 of the 85 cases in
`unknown/`, plus 33 scattered across typed directories. The other 14
`unknown/` cases get past detection and fail later; item 02's `stage`
field is what separates the two groups.

Known gap families to verify case-by-case: YAML frontmatter before the
keyword, `%%` comments and `%%{init}%%` directives, keyword variants,
and the `error`/`info` patterns — those two match on such short prefixes
that they can claim a case belonging to another type, which the bucket
list must confirm case by case rather than assume.

## Do

1. Build the per-case failure list from the scoreboard's `detect-fail`
   rows (item 02b step 3 — a plain pass/fail schema cannot produce this
   list, which is why 02b records `stage` and `error_class`). Bucket by
   syntactic cause. No pattern edits before the list exists.
2. Preprocessing lives where it will stay: if item 10 has landed, build
   detection inside `Notation::Mermaid`; if not, build a standalone
   pure `Sirena::Preprocessor` + keep `DIAGRAM_TYPE_PATTERNS` a data
   table so 10 relocates without rewriting. Never the same work twice.
3. Fix patterns per bucket, each with its corpus case as a spec.
4. Every remaining `unknown/` case ends oracle-invalid or fixed.

## Done when

- `DiagramTypeError` failures = oracle-invalid cases only.
- Zero oracle-valid `unknown/` cases remain unresolved — each is either
  passing or carries an oracle rejection. (Baseline: 85 cases, of which
  9 pass, 71 fail detection and 5 fail later in the pipeline.)
- Scoreboard updated; every pattern change carries a corpus-case spec.

## Files

`lib/sirena/engine.rb` or `lib/sirena/notation/mermaid.rb` (whichever
exists when this runs), `lib/sirena/preprocessor.rb` (new, only on the
pre-item-10 path), `spec/sirena/engine_spec.rb`.
