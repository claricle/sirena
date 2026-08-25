# 02 — SVG: one serializer

**Goal:** one declaration per SVG attribute instead of two.
**Size:** 1 PR. 10 files in `lib/sirena/svg/`, net about -150 lines.
**Prerequisite:** item 01.

**Half of this item already landed on main.** The escaping half is done;
what is left is deleting the dead lutaml mapping. Read the "Already
done" section before you plan anything.

## Already done — do not redo it

The escaping fix shipped in commits `248ec25`, `7f79ce8`, `898606b`,
`2c4e41a` and `7cd3804`:

- `lib/sirena/svg/escaping.rb` exists, with `escape_text`,
  `escape_attribute` and `strip_forbidden` for the code points XML
  cannot represent at all.
- `spec/sirena/svg/escaping_spec.rb` and
  `spec/sirena/svg/escaping_boundary_spec.rb` cover it.
- `scripts/corpus_sweep.rb` already parses output with REXML
  (`corpus_sweep.rb:16,33-39`) instead of checking for `<svg`.
- The hand-built third declaration is gone. `Element.writes_attributes`
  (`svg/element.rb:71`) is a declarative list, and every shape class
  uses it.

So this item no longer changes rendered output at all. **All of 01-06
are now pure refactors**, and `rake corpus:check` must show zero change
across every one of them.

## Why — what is still there

Each SVG attribute is still declared **twice**. `Svg::Text` declares `x`
as:

```
  1   attribute :x, :float                     <- Ruby accessor
  2   map_attribute 'x', to: :x                <- lutaml XML mapping
```

and then names it once more in `writes_attributes`, which is the list
`to_xml` actually walks.

**(2) is dead for output.** It only runs on the `from_xml` path, and
nothing in `lib/` or `scripts/` reads XML back. One spec does —
`spec/sirena/svg/escaping_boundary_spec.rb:137` calls
`Text.from_xml('<text>x</text>').to_xml`, and `svg/text.rb:54` explains
why: under `mixed: true`, lutaml 0.8 hands `content` back as an Array.
That spec is the only caller in the repo, and deleting the mapping means
deleting it too. Say so in the PR; do not discover it in CI.

Across `lib/sirena/svg/` that is 10 files with an `xml do` block and 105
`map_attribute` lines, none of which affects a single byte Sirena
writes.

## Decision (already made — do not re-open)

**Delete the lutaml `xml do` blocks. Keep the hand-written `to_xml`.**

Reasons, so you do not have to re-derive them:

- The mapping is dead code; deleting it changes no output at all.
- Keeping the hand-written path means output stays byte-identical, so
  `rake corpus:check` stays meaningful.
- Switching to lutaml's serializer would change attribute order,
  self-closing style and namespace prefixes across every diagram — a
  large diff with no benefit.

Keep `Lutaml::Model::Serializable` as the base class and keep the
`attribute` declarations — those are the accessors, and `Document#new`
relies on them. Only the `xml do ... end` blocks go.

## Steps

1. Delete the `xml do ... end` block from all 10 files in
   `lib/sirena/svg/` that have one. Delete `SvgNamespace` if nothing
   else uses it.
2. Delete `spec/sirena/svg/escaping_boundary_spec.rb`'s `from_xml`
   example (`:137`) and the `content`-as-Array comment in
   `svg/text.rb:54` that only exists to describe that path. Keep
   `Array(content).join` or simplify it — either way, prove it with the
   suite, not by reading.
3. Add the spec that is still missing: render one diagram of **every
   registered type** and parse the output with REXML. Nothing in
   `spec/` iterates `DiagramRegistry.types` today, so no check covers
   all 24. This is the one that keeps the escaping fix from regressing.

## Done when

- [ ] no file in `lib/sirena/svg/` contains an `xml do` block
- [ ] `grep -rn "map_attribute" lib/sirena/svg/` returns nothing
- [ ] a spec iterates `DiagramRegistry.types` and REXML-parses every
      type's output
- [ ] `rake corpus:check` shows **zero** change

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

`lib/sirena/svg/*.rb` (the 10 with an `xml do` block),
`spec/sirena/svg/escaping_boundary_spec.rb`, and one new spec that walks
the registry.
