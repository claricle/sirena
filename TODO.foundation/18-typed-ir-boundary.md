# 18 — Typed IR

**Owner ruling 2026-08-13: the typed IR is built in this foundation.**
Issue #2 records it as an architecture constraint — "renderers consume
source text, build a typed intermediate representation, delegate layout
to `elkrb`, and emit SVG" — and the issue's stated architecture is the
answer. This replaces the earlier "deferred until after PlantUML"
position, which was our reasoning rather than the author's instruction.

Can start: after 10 (the registry gives the IR a place to live), after
14's emit/accept survey, and after 16's PlantUML class spike — those two
are its design evidence. Gates item 12's **Done**, not its start.

## Why the old deferral argument still shapes this

The reason for deferring was real: Sirena's 24 transforms emit
materially different structures, so an IR designed from Mermaid alone
would encode Mermaid's assumptions and PlantUML would fight it.

That risk is managed by sequencing the evidence before the design, not
by postponing the work:

1. Item 14 owes a per-transform record of what each emits versus what
   elkrb accepts. That survey is this item's input.
2. Item 16's PlantUML class spike ships first, supplying the second
   notation's shapes — the data point the deferral said was missing —
   without waiting for all of item 12.
3. Only then is the IR fixed, and both notations migrate onto it.

So the ordering the deferral wanted is preserved. Only the phase
boundary moves: PlantUML lands ON the IR instead of the IR waiting on
PlantUML.

## What "notation-neutral" means here

The IR must not encode any notation's **semantics** — no Mermaid-only
keyword, no PlantUML-only relation kind, nothing naming a source
language. A construct that exists because one notation spells something
a particular way stays in that notation's plugin.

That is a different question from which **diagram categories** the IR
covers. Sirena renders three structurally different kinds:

- **graph-shaped** — flowchart, class, state, ER, C4, git, mindmap,
  sankey, and PlantUML class: nodes, edges, containment. Sankey belongs
  here despite looking like a chart: `SankeyTransform` emits `nodes:`
  and `flows:` with source/target connectivity (`sankey.rb:49`) and does
  its own layering, so it is a graph that declines elkrb rather than a
  data series.
- **pre-positioned** — block, quadrant, packet: the source dictates
  placement, so layout is not delegated.
- **data-shaped** — pie, radar, xychart: values and proportions, no
  node/edge model at all (`PieTransform` at `pie.rb:17` emits no node
  boxes).

  Each type's shape is confirmed against its transform, not assumed from
  its name — sankey was misfiled on exactly that mistake.

The IR covers all three. Only the first is graph-shaped and only the
first delegates to elkrb. That is not a Mermaid bias — PlantUML has
data-shaped and pre-positioned types too; they are simply not in phase
1's class-and-sequence slice.

**No category is exempt.** "This type passes through un-IR'd" would let
the foundation close with the architecture issue #2 asks for half-built.

## Do

1. Collect the evidence: item 14's emit/accept survey plus item 16's
   PlantUML class shapes. Write the comparison down — what is common,
   what is notation-specific, what is layout-specific.
2. Define the IR's three shapes from that comparison, using the
   notation-neutrality rule above as the test for every field.
3. Decide per Mermaid type which shape it maps to, and record it. A type
   whose mapping is unclear is resolved before implementation, not by
   whoever reaches it first.
4. Migrate Mermaid's transforms onto the IR one type at a time, corpus
   pass set unchanged at each step.
5. Migrate the PlantUML class spike onto it — the proof the IR is not
   Mermaid-shaped.
6. Update item 10's boundary spec. The boundary moves: transform output
   is no longer private per plugin, because the IR is deliberately
   shared. What stays private is each notation's PARSE output before it
   becomes IR.

## Done when

- The IR is defined, committed, and consumed by both Mermaid and the
  PlantUML class spike.
- Every Mermaid type maps to one of the three shapes. No exception list.
- No IR field names or encodes a notation-specific construct — asserted
  by a spec, not by inspection.
- The corpus pass set is unchanged across the migration, byte-identical
  wherever the renderer did not change.
- Item 10's boundary spec asserts the new boundary (parse output
  private, IR shared) and fails if a notation leaks its own shapes past
  it.
- `elkrb` consumes the IR's graph shape, not per-notation structures
  (item 14).

## Files

`lib/sirena/ir/**` (new), `lib/sirena/transform/*`,
`lib/sirena/notation/**`, `spec/sirena/ir/**` (new), and item 10's
boundary spec.
