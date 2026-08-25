# Review rules

Seven rules. Every PR in `TODO.architecture/` is checked against them,
and they are the fastest way to catch an overbuilt design before it
lands.

## R1 — No bare Hash crosses a layer boundary

If class A hands data to class B in a different layer, that data is a
class you can open and read. Not a Hash, not a Hash of Hashes.

Why: today there are 24 private hash shapes between `Transform` and
`Renderer`. To emit one, you read the renderer that consumes it. That
reverse-engineering is the single largest tax on corpus work.

Inside one class, a Hash is fine.

## R2 — An abstract method is enforced by a spec, or it is deleted

A base class that declares `raise NotImplementedError` and has no spec
walking every subclass is decoration. `Diagram::Base` declares two such
methods; 9-10 of 24 types do not honor them, and nothing catches it.

Every abstract contract gets a spec that iterates
`DiagramRegistry.types` and asserts it. If that spec is annoying to
write, the contract is wrong — fix the contract, don't skip the spec.

## R3 — Registration is data, not code

`lib/sirena.rb` is 328 lines: the same require-and-register block
copy-pasted 24 times. When the same block appears more than twice, it is
a table plus a loop.

## R4 — Rule of three

Do not build an abstraction until the third real case exists.

Two notations (Mermaid + PlantUML) justify a notation layer. One does
not. A plugin system for loading external notations, before a second
notation exists, is a guess about an API nobody has used yet.

## R5 — No new layer without deleting a layer

The pipeline currently holds five representations of one diagram. Any
change that adds a sixth must remove one. State in the PR description
which one.

## R6 — Delete before you gate

A gate protecting code that should be deleted costs twice: once to write
the gate, once to delete both. Before adding a ratchet, a floor, or a
lint pass over an area, ask whether that area survives the next item.

## R7 — One sentence per class

If you cannot say what a class owns in one sentence without "and", it
owns more than one thing.

`Renderer::Base` currently owns theme lookup, SVG path math, style
factories, and a no-op `add_arrow_marker` placeholder. That is four
things and a stub.

## The question that catches most of it

**"What does the user get when this item is done?"**

If the answer is "a scoreboard" or "a registry", the item is
infrastructure. Infrastructure is sometimes necessary — item 01 here is
exactly that — but if more than half the plan answers that way, the plan
has drifted from the product.
