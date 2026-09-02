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
files, and `spec/mermaid/corpus-verdicts.yml` sorts every one of them
into four buckets — re-measured 2026-08-27:

```
  valid      1032   mmdc rendered it
  artifact    632   extraction damage, not mermaid
  unknown     274   no evidence either way
  invalid      59   mmdc rejected it
             ────
             1997
```

The 274 unknowns are why 632 + 59 does not account for the rest.

**This split is provisional, and it is not yet the oracle.**
`scripts/corpus_verdicts.rb:11` says so: the verdicts come from unpinned
foreign sidecars and heuristic artifact detection.
`AGENTS.md:11` defines the oracle as the pinned toolchain, and permits
excluding a case only on oracle rejection. So 632 + 274 + 59 are set
aside on today's best evidence, not written off — `TODO.foundation/02a`'s
pin and `02b`'s regeneration are what turn this into a target you can
hold someone to.

Sweep run 2026-08-27, `bundle exec ruby scripts/corpus_sweep.rb`:

```
  valid      574/1032   55.6%    <- the number that matters
  unknown    129/274    47.1%
  invalid     18/59     30.5%
  artifact    15/632     2.4%
  raw        736/1997   36.9%    <- do not quote this one
```

**458 valid cases fail today.** That is the size of the job as
currently evidenced — subject to the pin above moving cases between
buckets.

The raw 36.9% is not a worse version of 55.6%; it is a different
question with a different denominator. It is *lower*, because it counts
632 artifacts and 59 rejections that sit outside today's evidence-backed
target — not because they are unrenderable. Sirena in fact renders 15 of
the artifacts and 18 of the rejections; that says nothing useful, which
is the point. Quote the valid-only figure, and say which one you mean.

**Re-run the sweep before quoting any of this.** These numbers moved
between two rounds of reviewing this very document — the flowchart work
on main took valid from 508 to 574 while the plan sat here saying 508.
Every figure on this page is a snapshot with a date on it, and the date
is the important half.

Everything in this directory exists to make closing that gap cheaper.

## Decisions already made

These are settled. If you find yourself weighing one of them, you have
been sidetracked — the answer is here.

| Question | Decision | What it means for you |
|---|---|---|
| How close to mermaid must output be? | **Geometry parity.** 8% node-centre, 15% dimension-aspect, per `TODO.foundation/14` | elkrb is the layout engine, not a hand-written approximation. Scenes for graph types must be shaped so elkrb output drops into them (see item 04). Renderers never invent coordinates |
| Can we break the API? | **Yes, but say so.** Pre-1.0 — though `v0.1.0` IS tagged and published on RubyGems, so "nothing released" is false. Breaking it is still the right call; it needs stating as a decision, not assumed from a wrong premise | No deprecated aliases, no shims. Rename anything |
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
- After item 07: **eight files** to add a new type (seven generated,
  plus the `TYPES` row), and nothing to reverse-engineer. Extending an
  existing type costs whatever the change costs — see
  `07-adding-a-type.md`, which stopped promising a number after three
  wrong ones.

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
   3-column grid stub. Ten renderers already name their input `layout`.
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
  Layout::<Type>                every type, one per type
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
scene = Layout.for(type).call(model, theme: theme, today: today)
Renderer.for(type, theme: theme).render(scene)
```

Detection has to come from somewhere, and after item 06 that somewhere
is `Notation::Mermaid`, reading the same `TYPES` table every lookup
below it uses.

`Renderer.for` takes the theme because that is where a renderer already
keeps it: `renderer/base.rb:42` is `initialize(theme: nil)` and `render`
takes one argument (`engine.rb:272` builds it with
`renderer_class.new(theme: theme)`). Keeping that shape means item 06
changes how a renderer is *found*, not how it is *called* — no renderer
signature migration, and no window where converted and unconverted
renderers want different arguments.

**Each `.for` returns a fresh instance.** `Layout::Base#call` stores the
theme and the date on the instance, so a cached one would share render
state between concurrent calls.

**That is the pipeline, not the whole method.** `Engine#render` still
resolves the theme, still takes `today` and `verbose`, and still turns
the `Svg::Document` a renderer returns into the String the public API
returns. Item 06 keeps all of that byte-identical. What it deletes is
the type constants and the hand-written dispatch, not the method's
surrounding contract.

The layout signature is `call(diagram, theme:, today:)` everywhere in
this plan.

Two ambient inputs, both keyword, both always passed. **Theme** because
layouts size boxes to text and text size comes from the theme.
**Today** because `gantt` resolves partial dates against a reference
date — `transform/gantt.rb:150` and `:155` read it — and the engine
already threads it through (`engine.rb:93`, `:107`). Dropping it from
the signature changes gantt output, which item 06's byte-identical
API criterion forbids.

Callers always pass both. **`Layout::Base#call` owns them**, stores
them, and calls the subclass's `#scene(diagram)`; `theme` and `today`
are private readers. Subclasses define only `scene` — they never
declare a keyword they do not read, because `Lint/UnusedMethodArgument`
would flag it. One signature is the point; per-type signatures put the
dispatch back. See `LAYERS.md`.

Two rules hold it together:

- **No bare Hash crosses a layer boundary.** Every arrow above is a class
  you can open and read. That is what removes the reverse-engineering.
- **Every type gets a Layout and a Scene.** An earlier draft deleted the
  two smallest — `Transform::InfoTransform` and
  `Transform::ErrorTransform`, 38 lines each — and handed the renderer
  the `Diagram` model. Withdrawn: `renderer/info.rb:71` reads
  `graph[:show_info]`, both renderers compute their own coordinates, and
  item 05's single document builder reads `width`/`height` off the
  Scene. They become the two smallest layouts instead, about twenty
  lines each. The pipeline has no optional-layout branch.

`WORKED-EXAMPLE.md` shows the pie type written both ways — the shape to
copy, with one gap it names at the bottom.

## Order of work

Strictly in order. Each step makes the next one smaller, and every step
after 01 is protected by 01.

| # | Item | Size | What it gives a user |
|---|---|---|---|
| 01 | Safety net: corpus check + contract spec | 2 PRs | nothing visible — but a real latent crash is closed and nothing breaks silently from here on |
| 02 | SVG: one serializer | 1 PR | nothing visible — the escaping fix it used to carry already landed on main |
| 03 | Name the layers honestly | 4 PRs, pure rename | nothing — the codebase becomes readable |
| 04 | Typed Scene between layout and renderer | 26 PRs — base, transition, and 24 conversions | fixes get roughly 2x cheaper from here on |
| 05 | Delete the boilerplate | 3 PRs | parse errors that name line, column and source, for all 24 types |
| 06 | Registry as data | 1 PR | — |
| 07 | Adding a type in an hour | 2 PRs | the point of the plan |
| 08 | Then the corpus burndown | ongoing | the pass rate finally moves |

**Items 01-03 and 06 change no rendered output at all.** Item 02 used to
be the exception, because it carried the escaping fix; that fix landed
on main ahead of this plan, so what is left of item 02 is a pure
deletion.

**Items 04 and 05 change the SVG, on purpose.** Item 04 sizes boxes
from theme font metrics, so `high_contrast` stops overflowing its own
text. Item 05 part C replaces hardcoded hex with theme colours.

**The corpus number must still not move.** It measures whether a case
renders well-formed output, not what that output looks like — a box
sized differently still passes. So the rule holds for all six items, and
items 04 and 05 keep their own unchanged-count criteria. If a PR in
01-06 moves the corpus number, something is wrong — see "Stop and ask"
below.

## How to work

- **One item at a time, in order.** Do not start 04 while 03 is open.
- **The item's Size line says how many PRs it is**, and that is the
  authority. Numbered steps are not PRs — item 01 has twelve steps in two
  PRs, item 04 has six steps across 26. Read the Size line first.
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
- `WORKED-EXAMPLE.md` — the pie type before and after, with one gap it
  names at the bottom.
- `DO-NOT-BUILD.md` — work that is real but premature, with the event
  that makes each one worth doing.
- `MAPPING.md` — how this relates to `TODO.foundation/`, and which of
  those items are still the reference for later work.
