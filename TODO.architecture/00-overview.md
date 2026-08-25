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

24 Mermaid diagram types are registered. Against the 1,997-case test
corpus in `spec/mermaid/`, about 31% render correctly today. Closing
that gap is the job. Everything in this directory exists to make closing
it cheaper.

## Decisions already made

These are settled. If you find yourself weighing one of them, you have
been sidetracked — the answer is here.

| Question | Decision | What it means for you |
|---|---|---|
| How close to mermaid must output be? | **Geometry parity.** 8% node-centre, 15% dimension-aspect, per `TODO.foundation/14` | elkrb is the layout engine, not a hand-written approximation. Scenes for graph types must be shaped so elkrb output drops into them (see item 04). Renderers never invent coordinates |
| Can we break the API? | **Yes, freely.** Pre-1.0, nothing released | No deprecated aliases, no shims. Rename anything |
| Is PlantUML real? | **Yes, next few months** | Item 06 keeps detection inside `Notation::Mermaid` rather than the engine, so PlantUML slots in. Still no plugin system — read `TODO.foundation/12` and `16` before item 06 |
| What are Scene classes built from? | **lutaml-model**, like the Diagram layer | `attribute` declarations only. **Never add an `xml do` block to a Scene** — Scenes are internal and never serialize to XML; that block is what caused the trouble in the Svg layer |

Geometry parity is the largest of these. It means the reference SVGs and
a reproducible mermaid toolchain **are** needed — see
`DO-NOT-BUILD.md`, where they are deferred to a named point in item 08
rather than dropped. Do not build them earlier; do not be surprised when
they arrive.

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
  Engine#detect_diagram_type        engine.rb:27, hardcoded regex table
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

`Engine#render` becomes three lines:

```ruby
model = Parser.for(type).parse(source)
scene = Layout.for(type)&.call(model) || model
Renderer.for(type).render(scene, theme: theme)
```

Two rules hold it together:

- **No bare Hash crosses a layer boundary.** Every arrow above is a class
  you can open and read. That is what removes the reverse-engineering.
- **A type with no geometry gets no Layout class.** About ten types
  today have a `Transform` that only copies fields into a hash
  (`Transform::InfoTransform` is 38 lines to copy three). Those get
  deleted and the renderer takes the `Diagram` model directly.

`WORKED-EXAMPLE.md` shows the pie type written both ways, in full.

## Order of work

Strictly in order. Each step makes the next one smaller, and every step
after 01 is protected by 01.

| # | Item | Size | What it gives a user |
|---|---|---|---|
| 01 | Safety net: corpus check + contract spec | 2 PRs | nothing visible — but a real latent crash is closed and nothing breaks silently from here on |
| 02 | SVG: one serializer, escape once | 1 PR | diagrams containing `<`, `&` or quotes stop producing broken SVG |
| 03 | Name the layers honestly | 4 PRs, pure rename | nothing — the codebase becomes readable |
| 04 | Typed Scene between layout and renderer | ~21 PRs, one per type | fixes get roughly 2x cheaper from here on |
| 05 | Delete the boilerplate | 3 PRs | parse errors that name line, column and source, for all 24 types |
| 06 | Registry as data | 1 PR | — |
| 07 | Adding a type in an hour | 2 PRs | the point of the plan |
| 08 | Then the corpus burndown | ongoing | the pass rate finally moves |

Items 01-06 change no rendered output. **Item 02 is the only exception,
and it changes output only where the output was already malformed.**
If a PR in 01, 03, 04, 05 or 06 moves the corpus number, something is
wrong — see "Stop and ask" below.

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
