# Sirena: changes to the foundation plan

*What we're changing in the plan, and why.*

## TL;DR

The foundation plan is a good plan for **measuring** the codebase. We're
adding a phase before it that **shapes** the codebase, because the shape
is what makes each of the ~1,380 remaining corpus fixes expensive.

Same destination, different order. Seven of the twenty original items
are unchanged and still the reference.

---

## Background, for anyone new to the repo

Mermaid is diagram-as-text. The official renderer (`mmdc`) is JavaScript
and needs Node plus a headless Chromium. **Sirena does the same job in
pure Ruby, with no Node and no browser.** That's the whole product.

24 Mermaid diagram types are registered. Against the 1,997-case corpus,
about 31% render correctly (614/1997). Closing that gap is the job.

---

## The problem we're fixing first

One diagram passes through five representations, three of which are
hand-written separately for each of the 24 types:

```
  source
    |
  Grammar (Parslet)          -> parse tree          rep 1
  Parser::Transforms::Pie    -> Diagram::Pie        rep 2/3   TYPED
  Transform::PieTransform    -> plain Hash          rep 4     UNTYPED
  Engine#layout_graph        -> 3-column grid stub
  Renderer::PieRenderer      -> Svg objects         rep 5
  Svg::Document#to_xml       -> hand-built String
```

Three things in that picture cost time on every single fix:

**1. Two different layers are both called "Transform."**
`Parser::Transforms::Pie` turns a parse tree into a model.
`Transform::PieTransform` turns a model into a Hash. Unrelated jobs, one
word.

**2. The layer called Transform is doing layout.** `Transform::Mindmap`
positions nodes; `Transform::XYChart` computes axis scales. Meanwhile
`Engine#layout_graph` — the method actually named layout — is a
3-column grid stub. Nine renderers already name their input `layout`.

**3. The typed model is flattened into an untyped Hash** right before
the renderer. There are 24 private, undocumented hash shapes. To change
what a layout emits, you read the renderer to find out what it expects.

**Net effect:** fixing one diagram type means touching five files across
five layers, plus reverse-engineering one undocumented contract. After
the structural work it's two files and nothing to reverse-engineer.

```
  new diagram type        5 files   (4 new + one row in the type table)
  new syntax on a type    2 files   (grammar + builder)
```

Those two numbers get asserted by a spec, not claimed.

---

## Three bugs the plan doesn't mention

Found while reviewing. All three are live, and all three are cheap now
and expensive later.

**A latent crash in the model layer.** `Diagram::Base` declares
`diagram_type` and `valid?` as abstract methods. Across the 24 types:

```
  bypass Diagram::Base entirely     4    architecture, block, gantt, requirement
  no diagram_type                  10    5 of them spell it `type`
  no valid?                         9
```

13 transforms call `diagram.valid?`, and those 13 happen to be a subset
of the 15 models that define it. Nothing crashes today **by
coincidence.** Move that check into the base class — an obvious cleanup
someone will make — and 9 types raise `NotImplementedError` in
production.

**The error taxonomy destroys the data the corpus harness needs.**
`Engine#render` collapses every non-detection failure into a single
`PipelineError`, with the backtrace concatenated into the message string
(`engine.rb:104-106`). So a corpus harness cannot tell a parse failure
from a render failure — and foundation item 05 derives its entire work
list from exactly that distinction.

**The theme never reaches the layout layer.** Every layout hardcodes
`DEFAULT_FONT_SIZE = 14` while renderers draw at
`theme.typography.font_size_normal`. The built-in `high_contrast` theme
sets 16.0 — so under that theme, every node is sized for 14pt text and
rendered at 16pt, and the text overflows its box.

---

## What changes in the plan

### 1. A structural phase goes in front (new)

Seven items, all mechanical, none changing rendered output except one
escaping fix:

```
  01  safety net        error taxonomy + contract spec + corpus.json
  02  SVG               one serializer, escape once
  03  naming            Transform -> Layout, pure rename
  04  typed Scene       kill the 24 undocumented hash shapes
  05  boilerplate       13 parsers, 9 doc-creators, 5 palettes
  06  registry          lib/sirena.rb 328 lines -> under 40
  07  adding a type     generator, shared examples, one onboarding page
```

**Why:** the burndown is the largest block of work in the project by an
order of magnitude. It's the one place where a 2x cost difference is
worth seven items of preparation.

### 2. Item 02 (corpus oracle) splits by time — it is NOT dropped

**Now:** a committed `corpus.json` of case -> pass/fail/stage. About 60
lines. Answers the only question items 01-07 ask: *did I just break
something?*

**Later, at elkrb time:** the hermetic toolchain pin, reference
regeneration with provenance, the comparator.

**Why:** the full version has ~18 acceptance criteria including
container digests, content-hash case identity with a migration manifest,
and specs for the test harness itself. That's a build-tooling product,
and it's the single biggest risk of the whole plan stalling in
infrastructure.

**Important:** with geometry parity as the agreed fidelity bar, the
toolchain pin is genuinely necessary — comparing against irreproducible
references measures noise. The original instinct was right; the
disagreement was only about *when*. It's scheduled, not deleted.

### 3. Item 10 (notation registry) shrinks

**Instead of:** a two-level registry, notation plugin objects, RubyGems
discovery for external notations, and a blocking API contract document.

**Do:** one type table plus convention-based class lookup. 328 lines
becomes under 40, and the dead top-level `self.render` at
`lib/sirena.rb:38` gets deleted.

**Why:** it's a plugin system for a second notation that doesn't exist
yet. The item itself notes the shape is settled but the API contract
isn't — that's the signal there isn't enough evidence to design it.
Build the notation layer in the PlantUML PR, from two real notations.
`Notation::Mermaid` with its own type table is already the seam.

### 4. Item 18 (typed IR) comes forward, scoped down

Build the typed contract now, Mermaid-only, deliberately non-general.

**Why:** deferring a *cross-notation* IR until PlantUML exists is
correct reasoning. But it isn't a reason to have **no** contract in the
meantime — 24 undocumented hash shapes is a cost being paid on every
corpus fix today. Expect to rewrite it when PlantUML lands; that's
cheap.

### 5. Item 09 (rubocop todo, 7,614 entries) moves later

**Why:** items 04-06 delete a large fraction of the files that debt is
parked in. Styling code you're about to delete costs twice. The original
item already spotted the collision with item 10 and resolved it with
"rebase onto it" — same signal.

### 6. Two items get simplified rather than deferred

- **Coverage floors:** one line floor, one branch floor, raised by hand.
  Not a 70 -> 80 -> 90 -> 97 timeline tied to other tracks' completion
  events — that coupling is a large part of what makes the dependency
  graph hard to follow, and it buys nothing a manual bump doesn't.
- **CI:** one workflow file, add a job when a gate exists. Not a lane
  skeleton with an extension contract and per-item lane ownership.

### 7. Item 13 (skills + agents) needs a decision

It's described as maintainer-local and untracked, while also being a
global blocker on all agent dispatch. A blocking dependency that isn't
in the repo can't be verified by whoever picks the work up. Either
commit it or drop it from the plan.

---

## What does NOT change

These are good work, still correct, still the reference. When their turn
comes, read them as written:

```
  04  XML escaping           research reused directly
  05  type detection         first task of the burndown
  06, 07  corpus burndown    per-type counts and bars stand
  08  lint, 109 live         small, can run any time
  11  docs truth             independent
  14  elkrb + layout parity  adopted IN FULL, including the metric contract
  15  docs site build        independent
  17  release + versioning   independent
```

Item 14's metric contract — node identity, normalisation, the equations,
overlap semantics, a metric for every non-box type — is the
best-calibrated part of either plan. Geometry comparison really is that
subtle. Adopted unchanged.

Item 01 (lutaml 0.8 migration) appears already landed: the gemspec is
`~> 0.8.0` as of commit 2702a09.

---

## Decisions made

```
  Fidelity        geometry parity with mermaid (8% node-centre,
                  15% dimension-aspect) -> elkrb is the layout engine
  API stability   break freely, pre-1.0, no deprecation shims
  PlantUML        real, next few months -> keep the seam, no plugin system
  Scene classes   lutaml-model, matching the Diagram layer
```

---

## Target architecture

```
  source
    |
  Notation::Mermaid          one data table (type -> regex)
    |
  Parser::<Type>             Grammar + Builder
    |
  Diagram::<Type>    TYPED   what the text MEANS      (semantics)
    |
  Layout::<Type>             only where geometry exists
    |
  Scene              TYPED   where things GO          (geometry)
    |
  Renderer::<Type>           Scene -> Svg objects
    |
  one serializer             escapes once
    v
  SVG string
```

`Engine#render` becomes three lines:

```ruby
model = Parser.for(type).parse(source)
scene = Layout.for(type)&.call(model, theme: theme) || model
Renderer.for(type).render(scene, theme: theme)
```

Two rules hold it together:

- **No bare Hash crosses a layer boundary.** Every arrow is a class you
  can open and read.
- **A type with no geometry gets no Layout class.** About ten of today's
  Transform classes only copy fields; those get deleted.

---

## The renames

Pure renames, no logic change. The corpus number must not move.

```
  BEFORE                              AFTER
  ------                              -----
  Parser::Transforms::Pie             Parser::Builders::Pie
    dir parser/transforms/              dir parser/builders/

  Transform::PieTransform             Layout::Pie
    dir transform/                      dir layout/
    Transform::Base                     Layout::Base
    TransformError                      LayoutError

  Engine#layout_graph                 Layout::Grid
  Engine#apply_fallback_layout          a class with one caller,
                                        explicitly temporary — elkrb
                                        replaces it later

  Engine::DIAGRAM_TYPE_PATTERNS       Notation::Mermaid::TYPES
```

**Class names become uniform.** Today three conventions are in use: 17
types use `XParser` / `XTransform` / `XRenderer`, seven use the bare type
name for transform and renderer (`GitGraph`, `Mindmap`, `Kanban`,
`Radar`, `XYChart`, `Packet`, `Treemap`), and one parser is bare
(`Parser::Architecture`). All become `Sirena::<Layer>::<Type>`:

```
  Parser::PieParser         ->  Parser::Pie
  Transform::PieTransform   ->  Layout::Pie
  Renderer::PieRenderer     ->  Renderer::Pie
  Transform::GitGraph       ->  Layout::GitGraph
```

The suffix repeats the namespace. Dropping it is also what lets the
registry find classes by convention instead of listing them.

**New:** `Notation::Mermaid`, `Layout::Scene`, `Layout::<Type>::Scene`.

**Deleted:** ~10 pass-through Layout classes, 5 private `DEFAULT_COLORS`
constants, 9 copies of `create_document_from_layout`, the no-op
`add_arrow_marker` placeholder, the `Treemap = TreemapParser` alias, and
the dead top-level `self.render` at `lib/sirena.rb:38`.

Pre-1.0, so no deprecation aliases — callers get updated and the old
names go.

---

## What a diagram type looks like, before and after

```
  BEFORE                              AFTER
  parser/pie.rb            48 ln      parser/pie.rb            ~8 ln
  parser/grammars/pie.rb  127 ln      parser/grammars/pie.rb  127 ln  unchanged
  parser/transforms/pie.rb 142 ln     parser/builders/pie.rb  142 ln  renamed
  diagram/pie.rb          114 ln      diagram/pie.rb          114 ln  unchanged
  transform/pie.rb         61 ln      layout/pie.rb           ~70 ln
  renderer/pie.rb         234 ln      renderer/pie.rb        ~150 ln
```

The parser becomes a declaration — that same 22-line body is currently
copy-pasted into 13 of the 24 parsers:

```ruby
class Parser::Pie < Base
  grammar Grammars::Pie
  builder Builders::Pie
end
```

---

## Layer contracts

One sentence each. If a class can't be described this way, it owns more
than one thing.

```
  Notation::Mermaid     which type a piece of text is     String -> Symbol
  Parser::<Type>        text into meaning                 String -> Diagram
  Diagram::<Type>       what the diagram SAYS             no geometry
  Layout::<Type>        where everything GOES             Diagram+Theme -> Scene
  Scene                 the computed geometry             no meaning
  Renderer::<Type>      shapes, colours, fonts            Scene+Theme -> Svg
  Svg::*                valid, escaped XML                -> String
```

Two boundaries that are easy to get wrong:

- **Diagram holds no coordinates.** Tempted to put `x` on a
  `Diagram::FlowchartNode`? It belongs on the Scene node.
- **Renderer computes no coordinates.** If a renderer does arithmetic on
  positions or angles, that arithmetic belongs in the layout. The
  renderer places shapes; it doesn't decide where they go.

**Nothing mutates its input.** Layout returns a new Scene; Renderer
returns a new document. Today `Engine#apply_fallback_layout` writes
`node.x =` in place — that matters because the comparator renders the
same input repeatedly, and two themes must give two independent results.

**Theme enters twice, for two different reasons:**

```
  Theme -> Layout     font metrics: how big is this text, so how big
                      must the box be that contains it
  Theme -> Renderer   colours, stroke widths, font family and size
```

That's the fix for the `high_contrast` overflow bug above. Any
measurement affecting size is a layout concern; any decision affecting
appearance is a renderer concern. Both get the theme; neither guesses.

**Each layer raises its own error, and the class survives to the
caller:** `DiagramTypeError`, `ParseError`, `LayoutError`, `RenderError`,
all under `Sirena::Error`. No more collapsing everything into
`PipelineError` with a stringified backtrace.

---

## Scene design

Scenes are lutaml-model, like the Diagram layer — `attribute`
declarations only, **never an `xml do` block** (Scenes are internal and
never serialize; that block is what created the triple-declaration mess
in the Svg layer).

**Graph types must use an ELK-shaped Scene.** Geometry parity is the
agreed bar, so elkrb computes positions later. If the Scenes already
mirror what ELK emits, that's a swap; if we invent a different shape
now, it's a redesign of all nine.

```ruby
class Node    # id, x, y, width, height, labels, children
class Edge    # id, source, target, sections{start/end/bend points}, labels
```

For `flowchart`, `class_diagram`, `state_diagram`, `er_diagram`, `c4`,
`requirement`, `architecture`, `block`, `mindmap`. Type-specific extras
(`shape`, `arrow_type`, `cardinality`) are fine; the geometry fields
aren't renamed.

**Everything else gets a Scene shaped by its own diagram.** A pie has
sectors, a gantt has bars on a date axis. Forcing those into nodes and
edges just recreates the untyped Hash with extra steps.

---

## Where to start

Read the code before writing any. Everything above is checkable against
the repo, and the fastest way to trust it — or find where it's wrong —
is to look.

Worth an afternoon each:

```
  lib/sirena.rb                 328 lines of copy-paste, plus a dead
                                self.render at line 38

  lib/sirena/engine.rb          the pipeline in one file: the regex
                                table at :27, the grid stub at :178,
                                the error wrapping at :104

  lib/sirena/transform/pie.rb   a "transform" that copies fields
  lib/sirena/transform/mindmap.rb  a "transform" that does layout
                                compare them and the naming problem
                                explains itself

  lib/sirena/renderer/pie.rb    then read the renderer that consumes
                                the hash pie.rb emits, and notice that
                                the contract only exists here

  lib/sirena/svg/text.rb        the same attribute declared three
                                times; work out which one runs
```

Then pick one diagram type and trace a single `.mmd` file all the way
through to SVG. That's the hour that makes the rest of this document
obvious.
