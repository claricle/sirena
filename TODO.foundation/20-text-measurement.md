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
`WIDE_CHAR_WIDTH_RATIO = 1.5` in `lib/sirena/renderer/flowchart.rb`, raised
from an initial `1.0` in this same PR.

**No scalar bounds it, and that is measured, not argued.** Real advances,
read from the font tables with `ttfunk`, Arial and Helvetica agreeing
exactly (`units_per_em` 2048):

    A = 0.667 em      @ = 1.015 em      W = 0.944 em

So the initial `1.0` was already exceeded by an ordinary `@`, which is why
the hint was raised to `1.5`. Widening further does not help past that,
because the characters that break it are not in the font at all:

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

## Resolution (2026-10-06)

Built: route 1, without the dependency. `TextMeasurement` sums per-glyph
advances from a table generated once from Liberation Sans Regular (SIL OFL,
metric-compatible with Arial; Arial itself is only a cross-check) by
`scripts/generate_text_advances.rb`. `ttfunk` stays out of the gemspec and
the bundle; only the dev-time generator needs it. `WIDE_CHAR_WIDTH_RATIO` is
gone: renderers reserve room as the measured width times
`Renderer::Base::SUBSTITUTE_FONT_HEADROOM` (1.2).

**The 0.889 gap, settled.** It does not reproduce. Headless Chrome 131
`getComputedTextLength` for `@` is 1.01514 em at 12, 16 and 100 px for Arial,
Helvetica, `sans-serif` and Arial Unicode MS, which is the `hmtx` advance
(2079/2048). Mermaid's own default stack (`"trebuchet ms", verdana, arial`)
gives 0.77 em, so a reading near 0.889 came from a different resolved font,
not from a flaw in the table.

**Accuracy against Chrome (Arial, 14 mixed strings, size 100):** predicted
over measured is 1.000 to 1.004; the one string off by more than 0.01 em
("Hello World", 5.17 against 5.15) is a kerning pair.

**Bounds** (also stated in the `TextMeasurement` class comment):

| bounded | only estimated | not bounded |
|---|---|---|
| every codepoint in the table (Latin, Greek, Cyrillic, punctuation, currency): exact in Liberation Sans, and in Arial wherever Arial has the glyph (five table codepoints have none in the macOS Arial.ttf checked). CJK and fullwidth at 1.0 em, the four Arabic ligature codepoints, zero-width marks: measured | emoji at 1.5 em, every other codepoint at 1.0 em | a font substituted for a glyph Arial lacks, other stacks (DejaVu, Verdana up to 1.19 times wider), bold, italic, shaping beyond the four ligatures |

A newline inside one label counts as a space, because every renderer draws a
label as one `<text>` and SVG collapses the newline. The class diagram draws
the stereotype and the name as two lines, so it measures each on its own, the
name at the 16 it is drawn at (regular widths; Chrome's bold Arial runs 1.04 to
1.11 times wider for ordinary names, which the box padding absorbs).

Effect on output: 491 of the 1997 corpus renders change bytes (flowchart 219,
class 161 across its two alias dirs, git 57, state 17, unknown 22, the rest
under 16), none changes between rendering and erroring. `conformance:check`
stays 1251/1251 and `corpus:check` stays clean.
