# 02 — SVG: one serializer, escape once

**Goal:** diagrams whose text contains `<`, `&` or a quote stop
producing broken SVG.
**Size:** 1 PR. 12 files in `lib/sirena/svg/`, net about -250 lines.
**Prerequisite:** item 01.

This is the only item in 01-06 that changes rendered output, and it
changes it only where the output was already malformed.

## Why

Every SVG element declares each attribute **three times**. `Svg::Text`
declares `x` as:

```
  1   attribute :x, :float                     <- Ruby accessor
  2   map_attribute 'x', to: :x                <- lutaml XML mapping
  3   %( x="#{x}")  in element_attributes      <- hand-built string
```

`Document#to_xml` calls `child.to_xml`, which uses (3).

**(2) is dead.** It only runs on the `from_xml` path, and nothing in
`lib/`, `spec/` or `scripts/` calls `from_xml` — verified by grep. The
comment in `svg/text.rb` about `content` arriving as an Array is
describing a code path that never executes.

Because output is assembled by string interpolation with no escaping
helper anywhere under `lib/sirena/svg/`, any diagram label containing
`<` or `&` produces invalid XML. `svg/text.rb:48` interpolates content
straight into `<text>...</text>`; `svg/element.rb:39` does the same for
every attribute value. The corpus already contains the proof case:
`spec/mermaid/sequence/025_spec_xss_spec_24.mmd` renders `Alice<img
src=` inside a `<text>` element. `scripts/corpus_sweep.rb:24` only
checks the outer `<svg>` shape, so it scores that as a pass.

## Decision (already made — do not re-open)

**Delete the lutaml `xml do` blocks. Keep the hand-written `to_xml`.**

Reasons, so you do not have to re-derive them:

- The mapping is dead code; deleting it changes no output at all.
- Keeping the hand-written path means output stays byte-identical apart
  from the escaping fix, so `rake corpus:check` stays meaningful.
- Switching to lutaml's serializer would change attribute order,
  self-closing style and namespace prefixes across every diagram — a
  large diff with no benefit.

Keep `Lutaml::Model::Serializable` as the base class and keep the
`attribute` declarations — those are the accessors, and `Document#new`
relies on them. Only the `xml do ... end` blocks go.

## Steps

1. Delete the `xml do ... end` block from all 12 files in
   `lib/sirena/svg/`. Delete `SvgNamespace` if nothing else uses it.
2. Add one escaping helper on `Svg::Element`, used by every attribute
   value and by text content:
   - always: `&` -> `&amp;`, `<` -> `&lt;`, `>` -> `&gt;`
   - in attribute values also: `"` -> `&quot;`
   - escape `&` first
3. Route every interpolation in `element.rb`, `text.rb` and the ten
   shape classes through it. After this there must be no
   `"#{...}"` of user-supplied data left unescaped.
4. Add `spec/sirena/svg/escaping_spec.rb`: a label containing
   `<img src=x onerror=1>`, `&`, `"` and `'` round-trips to escaped
   output.
5. Add a spec that renders one diagram of every registered type and
   parses the output with REXML (stdlib). This is the check that keeps
   the fix from regressing.
6. Tighten `scripts/corpus_sweep.rb`: parse the output rather than
   checking for `<svg`.

## Done when

- [ ] no file in `lib/sirena/svg/` contains an `xml do` block
- [ ] `grep -rn "map_attribute" lib/sirena/svg/` returns nothing
- [ ] the XSS corpus case produces XML that REXML parses
- [ ] every registered type's output parses
- [ ] `rake corpus:check` shows no regression (expect a small gain)

## Do not

- Do not add `svg_conform` or profile validation in this PR. Escaping is
  the bug; profile conformance (`marker-end` on path,
  `dominant-baseline`, font stacks, arbitrary hex fills) is a separate
  and larger question. `TODO.foundation/04` has the API research for it
  when its time comes.
- Do not remove `Lutaml::Model::Serializable` from these classes.
- Do not touch `lib/sirena/diagram/` — those models legitimately use
  lutaml.

## Files

`lib/sirena/svg/*.rb` (all 12), `spec/sirena/svg/escaping_spec.rb`
(new), `scripts/corpus_sweep.rb`.
