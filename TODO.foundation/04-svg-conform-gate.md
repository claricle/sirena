# 04 — XML correctness and the svg_conform gate

Can start: after 01 (needs lutaml-model 0.8 in-bundle). **Completion
after 02** — the per-case conformance rows and the scoreboard column
don't exist before it. Blocks: 12; with item 14's comparator, blocks
16's completion.

## Facts

**Sirena does not escape XML at all.** `lib/sirena/svg/text.rb:48`
interpolates content straight into `<text>…</text>`, and
`lib/sirena/svg/element.rb:39` interpolates every attribute value the
same way. There is no escape helper anywhere under `lib/sirena/svg/`.
The corpus already carries the proof case:
`spec/mermaid/sequence/025_spec_xss_spec_24.mmd` renders `Alice<img
src=` inside a `<text>` element and emits malformed XML.
`scripts/corpus_sweep.rb:24` only checks the outer SVG shape, so it
scores that output as a pass.

All sampled output also fails validation: `marker-end` on path,
`dominant-baseline` on text, Arial font stack, arbitrary hex fills.
API (verified 0.2.1): `SvgConform.validate` / `.validate_file` — there
is NO `validate_string`. Result object: `valid?`, `error_count`,
`errors`, `warnings`, `fixable_count`. Pin it: `svg_conform ~> 0.2.0`,
since the gate is written against that exact API.

## Do

1. **Escape XML at one boundary.** Centralize text-content and
   attribute-value escaping in `lib/sirena/svg/` so every element gets
   it by construction, not per renderer. Decide and document where
   trusted markup (if any) is allowed through — an escape hatch that
   isn't named becomes an accidental one.
2. **Profile decision**: read svg_conform's profiles; pick the one
   Claricle publication actually needs (any public question to the
   issue goes through the user). Fonts/colors may be profile policy —
   confirm before "fixing".
3. Fix structural issues in renderers: replace `dominant-baseline` with
   computed offsets; arrowheads via the profile-approved mechanism —
   verified against svg_conform's checks, not memory
   (dependency-contract-check gate).
4. Align the default theme (fonts, palette) with the profile — this is
   the "default Claricle-flavored theme" the issue asks for.
5. Conformance spec over every fixture and corpus-pass output.
   **Status is recorded per case in the scoreboard, not as a count** —
   a count lets one fix pay for one break. Any valid→invalid transition
   fails; the aggregate is derived from the rows.
6. Also tighten `scripts/corpus_sweep.rb`: a case whose output is not
   parseable XML is not a pass.
7. No runtime `apply_fixes` — conformant by construction; no invented
   lax profile.

## Done when

- Chosen profile documented with the reason.
- The named XSS corpus case renders parseable SVG with no injected
  element and no injected event attribute; ampersand and quote
  regressions cover the other two escape classes.
- 100% of corpus-pass and fixture outputs valid under the profile;
  spec in CI; per-case rows in the scoreboard.

## Files

`spec/svg_conformance_spec.rb`, `Gemfile`, `lib/sirena/svg/*`,
`lib/sirena/renderer/*`, `lib/sirena/theme/builtin/*`,
`scripts/corpus_sweep.rb`, scoreboard.
