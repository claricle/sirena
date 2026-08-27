# Sirena architecture plan

Read this page, then `LAYERS.md`, `RULES.md` and `WORKED-EXAMPLE.md`.
After that, start at `01-safety-net.md` and work in order.

`LAYERS.md` is the architecture itself — what each layer owns, what
flows between them, where the theme enters, and which errors each layer
raises. When you are unsure where a piece of code belongs, that page is
the answer.

## What the gem is

Mermaid is diagram-as-text — the fenced ```mermaid blocks you see in
GitHub READMEs. The official renderer (`mmdc`) is JavaScript and needs
Node plus a headless Chromium browser.

**Sirena does the same job in pure Ruby, with no Node and no browser.**
That is the whole product.

```
   INPUT: Mermaid text                          OUTPUT: SVG
   +------------------------+                  +------------------------+
   | pie title Sales        |                  | <svg width="500" ...>  |
   |   "Apples"  : 42       |  --> sirena -->  |   <path d="M 250 200   |
   |   "Oranges" : 58       |                  |      L 250 50 A ..."/> |
   +------------------------+                  |   <text>Apples</text>  |
                                               +------------------------+
```

24 Mermaid diagram types are registered. `spec/mermaid/` holds 1,997
files, but a third of them are not mermaid: `spec/mermaid/corpus-verdicts.yml`
marks 632 as extraction artifacts and 59 as cases mmdc itself rejected.
**1,032 are cases mermaid accepts, and Sirena renders 508 of them — 49.2%.**

**524 valid cases still fail.** That is the size of the job. Measured
2026-08-25 with `bundle exec ruby scripts/corpus_sweep.rb`; never quote
a hand-written figure, and never use the raw 33.4% over all 1,997 files
— it counts files mermaid cannot parse either.

Everything in this directory exists to make closing that gap cheaper.

## Decisions already made

These are settled. If you find yourself weighing one of them, you have
been sidetracked — the answer is here.

| Question | Decision | What it means for you |
|---|---|---|
| How close to mermaid must output be? | **Geometry parity.** 8% node-centre, 15% dimension-aspect, per `TODO.foundation/14` | elkrb is the layout engine, not a hand-written approximation. Scenes for graph types must be shaped so elkrb output drops into them (see item 04). Renderers never invent coordinates |
| Can we break the API? | **Yes, freely.** Pre-1.0, nothing released | No deprecated aliases, no shims. Rename anything |
| Is PlantUML real? | **Yes, next few months** | Item 06 keeps detection inside `Notation::Mermaid` rather than the engine, so PlantUML slots in. Still no plugin system — read `TODO.foundation/12` and `16` before item 06 |
| What are Scene classes built from? | **lutaml-model**, like the Diagram layer | `attribute` declarations only. **Never add an `xml do` block to a Scene** — Scenes are internal and never serialize to XML; that block is what caused the trouble in the Svg layer |
| What coordinates does a Scene hold? | **Final canvas ones.** The renderer writes `x` and `y` out verbatim | No origin attribute, no offset applied at render time. The padding three renderers add by hand today (`git_graph.rb:48`, `mindmap.rb:48`, `kanban.rb:45`) moves into the layout, and so does `packet`'s title offset. One coordinate space — see item 04 |
| How is the `Diagram::Base` contract enforced? | **By whichever table is the single source of types.** One spec iterates that table | Two phases, and they are not a contradiction. Item 01 adds a `model:` row to `DiagramRegistry` and iterates `DiagramRegistry.types`, because the registry is the only table that knows which *class* serves a type. A second list exists — `Engine::DIAGRAM_TYPE_PATTERNS` — but it knows only how to *detect* a type, so it cannot carry the contract. That is exactly why item 01 also asserts the two sets match. Item 06 replaces the registry with `Notation::Mermaid::TYPES`, resolves the model by convention, and the spec iterates `TYPES` instead. Canonical fixtures are the second layer in both phases, proving the parser builds the model it declared |
| Is the cross-notation typed IR in this foundation? | **Yes.** Owner ruling, 2026-08-13, `TODO.foundation/18` | It is NOT deferred past PlantUML, and item 04 does not replace it. Item 04 is the layout→renderer boundary; item 18 is the notation→layout one. Both exist. See "The IR, and what the owner ruled" below |

Geometry parity is the largest of these. It means the reference SVGs and
a reproducible mermaid toolchain **are** needed — see
`DO-NOT-BUILD.md`, where they are deferred to a named point in item 08
rather than dropped. Do not build them earlier; do not be surprised when
they arrive.

## The IR, and what the owner ruled

An earlier draft of this plan deferred the cross-notation typed IR until
after PlantUML shipped, and treated item 04 as its smaller replacement.
**That is overruled.** `TODO.foundation/18` carries an owner ruling dated
2026-08-13: the typed IR is built in this foundation, because Issue #2
states it as the architecture. The old deferral was our reasoning, not
the author's instruction.

So the plan now says two things at once, and they do not conflict:

- **Item 04 is the layout→renderer boundary.** Scenes carry geometry —
  where things go. They are Mermaid-shaped on purpose and they are what
  removes the 24 undocumented hash shapes. Nothing about item 18 changes
  that, and nothing in item 04 waits for it.
- **Item 18 is the notation→layout boundary.** The IR carries meaning —
  what a diagram says, in terms no notation owns. It is still foundation
  work, it still has its own prerequisites, and item 04 does not stand in
  for it.

Item 18's ordering is unchanged from `TODO.foundation/18`: it starts
after item 10, after item 14's emit/accept survey (`docs/emit-accept-survey.md`),
and after item 16's PlantUML class spike. Those two are its design
evidence, and sequencing the evidence is what replaced the deferral.

**One consequence to see clearly.** This plan schedules item 14 at item
08 step 3, which is late. Item 18 cannot start before 14's survey
exists, so ruling the IR into the foundation also means that survey is
now on the critical path for item 18 — either 14 moves earlier than
step 3, or item 18 lands after it. That is a scheduling decision this
plan does not make; it is flagged here so nobody discovers it at item 18.

## The one goal

**Make the next Mermaid change cheap.**

Mermaid ships changes constantly — new syntax on existing types, new
types, changed defaults. Every decision in this plan is judged by one
question: when flowchart syntax changes next month, how many files does
someone touch, and do they have to reverse-engineer anything first?

- Today: **five files** across five layers, plus an undocumented
  contract you learn by reading the renderer.
- After item 07: **two files** to extend an existing type, **five** to
  add a new one, and nothing to reverse-engineer.

The same question decides the geometry work. With parity as the bar, a
layout fix must be a change to one layout class that elkrb feeds — not a
change scattered across a transform, a renderer and an engine stub.

## The pipeline today

```
  source
    |
  Engine#detect_diagram_type        engine.rb:32, hardcoded regex table
    |
  DiagramRegistry.get(:pie)         -> {parser:, transform:, renderer:}
    |
  Grammars::Pie          (Parslet)  -> parse tree        rep #1
    |
  Parser::Transforms::Pie           -> Diagram::Pie      rep #2/#3  TYPED
    |
  Transform::PieTransform           -> plain Hash        rep #4     UNTYPED
    |
  Engine#layout_graph               -> 3-column grid stub, no-op for most types
    |
  Renderer::PieRenderer             -> Svg objects       rep #5
    |
  Svg::Document#to_xml              -> hand-built String
    v
  "<svg>...</svg>"
```

Five representations of one diagram. Three of them are hand-written per
type, 24 times over.

Three problems in that picture, and each one costs time on every fix:

1. **`Parser::Transforms::X` and `Transform::X` are different layers
   with the same name.** Unrelated jobs, one word.
2. **The layer called `Transform` is doing layout.** `Transform::Mindmap`
   positions nodes; `Transform::XYChart` computes axis scales. Meanwhile
   `Engine#layout_graph` — the method actually named layout — is a
   3-column grid stub. Nine renderers already name their input `layout`.
3. **The typed model is flattened into an untyped Hash** right before the
   renderer. 24 private, undocumented hash shapes.

## The pipeline we want

```
  source
    |
  Notation::Mermaid.detect      one data table (type -> regex)
    |
  Parser::<Type>                Grammar (Parslet) + Builder
    |
  Diagram::<Type>      TYPED    what the text MEANS      (semantics)
    |
  Layout::<Type>                optional - only where geometry exists
    |
  Layout::<Type>::Scene TYPED   where things GO          (geometry)
    |
  Renderer::<Type>              Scene -> Svg objects
    |
  one serializer                escapes once
    v
  SVG string
```

`Engine#render`'s **core pipeline** becomes four lines:

```ruby
type  = Notation::Mermaid.detect(source)
model = Parser.for(type).parse(source)
scene = Layout.for(type)&.call(model, theme: theme) || model
Renderer.for(type).render(scene, theme: theme)
```

Detection has to come from somewhere, and after item 06 that somewhere
is `Notation::Mermaid`, reading the same `TYPES` table every lookup
below it uses.

**That is the pipeline, not the whole method.** `Engine#render` still
resolves the theme, still takes `today` and `verbose`, and still turns
the `Svg::Document` a renderer returns into the String the public API
returns. Item 06 keeps all of that byte-identical. What it deletes is
the type constants and the hand-written dispatch, not the method's
surrounding contract.

The layout signature is `call(diagram, theme:)` everywhere in this plan.
Layouts size boxes to text, and text size comes from the theme — see
`LAYERS.md`.

Two rules hold it together:

- **No bare Hash crosses a layer boundary.** Every arrow above is a class
  you can open and read. That is what removes the reverse-engineering.
- **A type with no geometry gets no Layout class.** Two of today's
  `Transform` classes only copy fields into a hash —
  `Transform::InfoTransform` and `Transform::ErrorTransform`, 38 lines
  each to copy three or four. `Transform::PieTransform` (61 lines) is
  the borderline third: it copies, but it also reads each slice's angle
  and percentage. Those get deleted and the renderer takes the `Diagram`
  model directly. Every other `Transform` computes geometry, so the
  count is two or three, not ten — check before you delete.

`WORKED-EXAMPLE.md` shows the pie type written both ways, in full.

## Order of work

Strictly in order. Each step makes the next one smaller, and every step
after 01 is protected by 01.

| # | Item | Size | What it gives a user |
|---|---|---|---|
| 01 | Safety net: corpus check + contract spec | 2 PRs | nothing visible — but a real latent crash is closed and nothing breaks silently from here on |
| 02 | SVG: one serializer | 1 PR | nothing visible — the escaping fix it used to carry already landed on main |
| 03 | Name the layers honestly | 4 PRs, pure rename | nothing — the codebase becomes readable |
| 04 | Typed Scene between layout and renderer | ~21 PRs, one per type | fixes get roughly 2x cheaper from here on |
| 05 | Delete the boilerplate | 3 PRs | parse errors that name line, column and source, for all 24 types |
| 06 | Registry as data | 1 PR | — |
| 07 | Adding a type in an hour | 2 PRs | the point of the plan |
| 08 | Then the corpus burndown | ongoing | the pass rate finally moves |

**Items 01-06 change no rendered output at all.** Item 02 used to be the
exception, because it carried the escaping fix; that fix landed on main
ahead of this plan, so what is left of item 02 is a pure deletion. If a
PR in any of 01-06 moves the corpus number, something is wrong — see
"Stop and ask" below.

## How to work

- **One item at a time, in order.** Do not start 04 while 03 is open.
- **One PR per numbered step** inside an item, unless the item says
  otherwise.
- **Run `rake corpus:check` before opening every PR.** After item 01 this
  is the whole safety net; it takes seconds and it is not optional.
- **Put the expected corpus effect in the PR description**: "no change"
  or "+N cases, listed". A surprise is a bug.
- **Each item has a Size line.** If your change is more than about twice
  that, stop — you have found something the plan did not know about.
  Write down what it is and ask. That is a useful outcome, not a failure.

## Stop and ask if

- A rename or refactor changes the corpus number.
- An item needs a design decision the file does not already make. Every
  decision in this plan is already made; if one is missing, it is an
  oversight worth raising rather than filling in.
- You find yourself building something in `DO-NOT-BUILD.md`.
- A step turns out to be impossible as written. Some of these files
  describe code that does not exist yet; the description may be wrong.

## Reference

- `LAYERS.md` — the layer contracts. The architecture in one page.
- `RULES.md` — seven review rules, one page. Read before item 01.
- `WORKED-EXAMPLE.md` — the pie type before and after, in full.
- `DO-NOT-BUILD.md` — work that is real but premature, with the event
  that makes each one worth doing.
- `MAPPING.md` — how this relates to `TODO.foundation/`, and which of
  those items are still the reference for later work.
