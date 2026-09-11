# 20 — text measurement, and the sizing it makes possible

Independent of every other item; nothing blocks it and it blocks nothing
today. It exists because PR #23 closed two overflow Highs and could not
close the third, and the reason is architectural rather than a bug.

Raised 2026-09-10 from a Codex round on `flowchart-invisible-link` that
declined to call the remaining clipping fixed: *"Closing this requires
measuring or controlling rendered text geometry... Accepting best-effort
sizing would require an explicit change to the acceptance contract."*
Owner ruled best-effort sizing acceptable, with this card opened.

## Facts

Sirena sizes text by counting characters. `TextMeasurement` multiplies
`font_size * 0.5` per character, and every transform sizes its boxes from
that. Self-loop label overflow uses a separate, wider hint,
`WIDE_CHAR_WIDTH_RATIO = 1.0` in `lib/sirena/renderer/flowchart.rb`.

**No scalar bounds it, and that is measured, not argued.** Real advances,
read from the font tables with `ttfunk`, Arial and Helvetica agreeing
exactly (`units_per_em` 2048):

    A = 0.667 em      @ = 1.015 em      W = 0.944 em

So `1.0` is already exceeded by an ordinary `@`. Widening further does not
help, because the characters that break it are not in the font at all:

    U+4E2D  中     ABSENT from Arial and Helvetica
    U+FDFD  ﷽     ABSENT from Arial and Helvetica, renders at 6.49 em

**A renderer substitutes a font sirena has never seen for those**, so no
table keyed on sirena's own font stack can predict their width. That is the
architectural fact this card exists for.

Unicode properties do not rescue it either. U+FDFD has East Asian Width
`N` (Neutral) — the same class as many ordinary characters — and its width
comes from the font's ligature substitution table, which no codepoint
property describes:

    python3 -c "import unicodedata as u; print(u.east_asian_width('A'), u.east_asian_width('﷽'))"
    -> Na N

Mermaid does not have this problem because it renders in a browser and
reads the laid-out geometry back. Measured, same three labels:

    flowchart LR, viewBox width      10x W    348.7
                                     10x 中   375.6
                                     3x  ﷽    523.9

Sirena is pure Ruby with no browser and no font metrics dependency
(`ttfunk` is NOT declared; it resolved only because another gem pulls it in).

**One number is unexplained and should be settled before any work starts.**
Chrome's `getComputedTextLength` gives `@` as 0.889 em; the font's own
`hmtx` advance is 1.015 em. A 14% gap on the single character the current
hint was calibrated against. Until that is understood, any new constant is
built on an unverified reading.

## The routes, with what each actually buys

| route | closes | costs |
|---|---|---|
| `ttfunk` glyph advances | ordinary scripts, exactly | a declared dependency, plus a font file to read — Arial is not redistributable, so it means bundling metrics or reading the host's fonts, which is platform- and CI-dependent |
| a shaping engine | ligatures, Arabic joining, Devanagari conjuncts | HarfBuzz has no pure-Ruby port; bindings mean a native extension |
| a browser | everything, exactly as mermaid does | the heavy dependency this gem exists to avoid |

## Bars

- **Not a blocker for any current PR.** Best-effort sizing plus explicit
  clipping is the accepted contract as of 2026-09-10. Overflow is a
  cosmetic clip of a label tail, never a distorted or escaped diagram —
  bends and box geometry are computed exactly and are unaffected.
- Any work here starts by resolving the Chrome-versus-`hmtx` gap above.
  A constant derived from an unreconciled measurement is the defect this
  card was opened to stop repeating.
- Whatever is built must state which glyphs it can and cannot bound.
  "Text is measured now" is the claim that would make the next overflow
  finding harder to see, not easier.

## Related

The deep-namespace limit is the same shape and is already accepted on the
same terms: sirena dies at roughly 250 nesting levels where mmdc renders,
because Ruby's thread VM stack size is fixed at interpreter startup and a
library cannot change it. Recorded as a capability gap, not a defect.
