# 05 — Diagram type detection fixes

Status (reconciled 2026-10-10): **complete.** The current corpus scoreboard
records all 37 oracle-valid cases in `unknown/` as passing. Its other 48 rows
are classified, not unresolved: 44 extraction artifacts and four
oracle-invalid sources. The only detection-stage failures are those artifacts
plus the oracle-invalid `unknown/055`; no oracle-valid case fails detection.

The implementation also carries the required evidence. `Source.split` removes
frontmatter, directives and comments before `Notation::Mermaid.detect_type`
runs, with the preamble behavior covered in `source_spec.rb`,
`engine_preamble_spec.rb` and the directive/comment cases in `engine_spec.rb`.
The pattern changes that moved scoreboard rows are locked to corpus cases:
bare `gantt` and `pie` use `gantt/023`, `gantt/025` and `pie/025`, and
`flowchart-elk` uses `unknown/012`, alongside negative boundary examples. The
additional direction-glyph boundary has direct mmdc-parity examples because no
corpus row exercised it. Detection order, including the short `info` and
`error` prefixes, remains explicit in `Notation::Mermaid::TYPES` rather than
being inferred from directory names.

Can start: after 02 (needs the failure list). Completion also needs 03a
— this item changes behavior, so its PRs need the changed-line gate.
Small; unblocks corpus cases across many types.

## Facts

104 corpus failures are `DiagramTypeError` — 71 of the 85 cases in
`unknown/`, plus 33 scattered across typed directories. The other 14
`unknown/` cases get past detection: 9 render successfully and 5 fail
later in the pipeline. Item 02's `stage` field is what separates the
three groups.

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

Complete. `DiagramTypeError` is absent from every oracle-valid scoreboard row;
the remaining detection failures are outside the valid denominator (extraction
artifacts, plus one pinned-oracle rejection). Zero oracle-valid `unknown/`
cases remain unresolved: 37/37 pass. The scoreboard records every row, and the
corpus-driven pattern changes carry the corpus-case specs named in the status
above; the extra boundary-only change carries direct parity specs.

The original baseline remains historically useful: 85 cases, of which nine
passed, 71 failed detection and five failed later in the pipeline. Artifact
classification was added after that baseline, so completion distinguishes
artifacts from pinned-oracle rejections instead of relabeling damaged extracted
text as valid Mermaid.

## Files

`lib/sirena/engine.rb` or `lib/sirena/notation/mermaid.rb` (whichever
exists when this runs), `lib/sirena/preprocessor.rb` (new, only on the
pre-item-10 path), `spec/sirena/engine_spec.rb`.
