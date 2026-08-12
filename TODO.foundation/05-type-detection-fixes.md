# 05 — Diagram type detection fixes

Can start: after 02 (needs the failure list). Small; unblocks corpus
cases across many types.

## Facts

104 corpus failures are `DiagramTypeError` (71 in `unknown/`, rest
scattered). Known gap families to verify case-by-case: YAML frontmatter
before the keyword, `%%` comments and `%%{init}%%` directives, keyword
variants, and the dangerously broad `error`/`info` patterns.

## Do

1. Build the per-case failure list from the scoreboard; bucket by
   syntactic cause. No pattern edits before the list exists.
2. Preprocessing lives where it will stay: if item 10 has landed, build
   detection inside `Notation::Mermaid`; if not, build a standalone
   pure `Sirena::Preprocessor` + keep `DIAGRAM_TYPE_PATTERNS` a data
   table so 10 relocates without rewriting. Never the same work twice.
3. Fix patterns per bucket, each with its corpus case as a spec.
4. Every remaining `unknown/` case ends oracle-invalid or fixed.

## Done when

- `DiagramTypeError` failures = oracle-invalid cases only.
- Scoreboard updated; every pattern change carries a corpus-case spec.

## Files

`lib/sirena/engine.rb` or `lib/sirena/notation/mermaid.rb`,
`spec/sirena/engine_spec.rb`.
