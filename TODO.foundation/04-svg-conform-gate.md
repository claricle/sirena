# 04 — svg_conform conformance gate

Can start: after 01 (needs lutaml-model 0.8 in-bundle). Blocks: 12.

## Facts

All sampled output fails validation: `marker-end` on path,
`dominant-baseline` on text, Arial font stack, arbitrary hex fills.
API (verified 0.2.1): `SvgConform.validate` / `.validate_file` — there
is NO `validate_string`. Result object: `valid?`, `error_count`,
`errors`, `warnings`, `fixable_count`.

## Do

1. **Profile decision first**: read svg_conform's profiles; pick the one
   Claricle publication actually needs (any public question to the
   issue goes through the user). Fonts/colors may be profile policy —
   confirm before "fixing".
2. Fix structural issues in renderers: replace `dominant-baseline` with
   computed offsets; arrowheads via the profile-approved mechanism —
   verified against svg_conform's checks, not memory
   (dependency-contract-check gate).
3. Align the default theme (fonts, palette) with the profile — this is
   the "default Claricle-flavored theme" the issue asks for.
4. Conformance spec over every fixture and corpus-pass output; failure
   counts are a scoreboard column (may only shrink to zero).
5. No runtime `apply_fixes` — conformant by construction; no invented
   lax profile.

## Done when

- Chosen profile documented with the reason.
- 100% of corpus-pass and fixture outputs valid under it; spec in CI.

## Files

`spec/svg_conformance_spec.rb`, `Gemfile`, `lib/sirena/renderer/*`,
`lib/sirena/theme/builtin/*`, scoreboard.
