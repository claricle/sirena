# Sirena: changes to the foundation plan

*What we're changing in the plan, and why.*

## TL;DR

The foundation plan is a good plan for **measuring** the codebase. We're
adding a phase before it that **shapes** the codebase, because the shape
is what makes each of the 458 remaining corpus fixes expensive.

Same destination, different order. Ten of the nineteen original items
are unchanged and still the reference — item 18 keeps its content and
gains one criterion, which is why an earlier count said nine.

---

## Background, for anyone new to the repo

Mermaid is diagram-as-text. The official renderer (`mmdc`) is JavaScript
and needs Node plus a headless Chromium. **Sirena does the same job in
pure Ruby, with no Node and no browser.** That's the whole product.

24 Mermaid diagram types are registered. `spec/mermaid/` holds 1,997
files, but a third of them are not mermaid — 632 extraction artifacts
and 59 cases mmdc rejected, per `spec/mermaid/corpus-verdicts.yml`.
Against the **1,032 cases mermaid accepts, Sirena renders 508 — 49.2%**,
leaving **458** to fix (measured 2026-08-27,
`bundle exec ruby scripts/corpus_sweep.rb`). Closing that gap is the job.

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
the structural work it is bounded by the change itself, and there is
nothing to reverse-engineer.

```
  new diagram type        8 files   (7 new + one row in the type table)
  new syntax on a type    varies    (1 to 5, measured — see item 07)
```

The eight-file count gets asserted by a spec, not claimed. The syntax
cost does not — item 07 measured four commits and found no bound worth
promising.

---

## Three bugs the plan doesn't mention

Found while reviewing. All three are live, and all three are cheap now
and expensive later.

**A latent crash in the model layer.** `Diagram::Base` declares
`diagram_type` and `valid?` as abstract methods. Across the 24 types
(measured 2026-08-25 by introspecting the model each parser returns):

```
  bypass Diagram::Base entirely     4    architecture, block, gantt, requirement
                                         -> valid? raises NoMethodError
  inherit Base#valid?, which raises 6    git_graph, mindmap, packet, radar,
                                         treemap, xychart
                                         -> NotImplementedError
  so: no working valid?            10
  no diagram_type                  10    5 of them spell it `type`
  define their own valid?          14
```

13 transforms call `diagram.valid?`, and those 13 are a subset of the 14
that define one — kanban defines one nobody calls. Nothing crashes today
**by coincidence.**

The obvious cleanup — move the check into `Transform::Base` — buys less
than it looks, and that is the part worth knowing:

- 7 transforms don't inherit `Transform::Base` at all, and they are
  exactly the 6 `NotImplementedError` types plus kanban. The moved check
  never runs for them.
- It reaches the other 4, which raise `NoMethodError`.
- `NotImplementedError` inherits `ScriptError`, not `StandardError`, so
  `engine.rb:119` doesn't catch it. It escapes `PipelineError` and
  reaches the caller raw.

**The error taxonomy destroys the data the corpus harness needs.**
`Engine#render` collapses every non-detection failure into a single
`PipelineError`, with the backtrace concatenated into the message string
(`engine.rb:119-121`). So a corpus harness cannot tell a parse failure
from a render failure — and foundation item 05 derives its entire work
list from exactly that distinction.

**The theme never reaches the layout layer.** Nine layouts size text at
a hardcoded 14 — seven via `DEFAULT_FONT_SIZE = 14`, two via a bare
literal — while renderers draw at `theme.typography.font_size_normal`.
The built-in `high_contrast` theme sets 16.0, so under that theme every
node is sized for 14pt text and rendered at 16pt, and the text overflows
its box. The other 15 layouts never measure text at all.

---

## What changes in the plan

### 1. A structural phase goes in front (new)

Seven items, all mechanical. None changes whether a case renders
well-formed output; 04 and 05 change what that output looks like, on
purpose:

```
  01  safety net        error taxonomy + contract spec + scoreboard/corpus.json
  02  SVG               one serializer, escape once
  03  naming            Transform -> Layout, pure rename
  04  typed Scene       kill the 24 undocumented hash shapes
  05  boilerplate       13 parsers, 9 doc-creators, 5 palettes (3 names)
  06  registry          lib/sirena.rb 328 lines -> under 40
  07  adding a type     generator, shared examples, one onboarding page
```

**Why:** the burndown is still the largest block of work in the project,
and it's the one place where a 2x per-fix cost difference is worth seven
items of preparation.

**One correction worth stating, because it cuts against us.** An earlier
draft of this argument said "~1,380 remaining corpus fixes". That was
1997 minus 614 — the whole corpus minus what passed — and it counted 632
extraction artifacts and 59 mmdc rejections as work. The real number is
**458**, measured against evidence-valid cases only. That is 3x smaller
than we claimed.

Does the argument survive? Yes, but on the per-fix cost rather than the
case count:

- 458 fixes is still an order of magnitude more work than the seven
  structural items, which are **39 PRs** of mechanical change. Item 04 is
  26 of them.
- The work is concentrated, which makes the structural case stronger
  rather than weaker: flowchart holds 128 and class holds 143, so 271 of
  the 458 land in two types whose grammars, layouts and renderers are
  exactly the files items 03-05 rewrite. Paying the untyped-hash tax 337
  times in two files is the case for fixing the files first.
- What we can no longer say is "a thousand cases justify anything".
  Seven preparatory items in front of 458 fixes is a judgment call, not
  an arithmetic one. It is the right call, and it is a call.

### 2. Item 02 (corpus oracle) splits by time — it is NOT dropped

**Now:** a committed `scoreboard/corpus.json` of case -> pass/fail/stage,
with each case's oracle verdict. About 60 lines. Answers the only
question items 01-07 ask: *did I just break something?*

**It is the scoreboard's first column, not a second tracker.** `AGENTS.md`
says every ratchet is a column in `scoreboard/` and that a rival
mechanism must not be invented, so this ships that directory early with
one column in it. Items 04, 05, 06, 07, 08, 11 and 14 all name the
scoreboard in their Done-when criteria; none of them changes, and all of
them still mean the same place.

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

**What does NOT shrink:** item 10's boundary ruling. `TODO.foundation/10:25-36`
says today's per-notation transform shapes are **interim, with item 18 as
their successor** — after the IR lands, the IR is deliberately shared and
only each notation's parse output stays private. Write any boundary
assertion so item 18 updates it rather than deletes it, and don't
describe today's shapes as permanent. That is the item's own wording and
it survives the shrink.

### 4. Item 18 (typed IR) stays as written, plus one criterion

An earlier draft of this section said item 18 "comes forward, scoped
down" and that item 04 was its smaller replacement. **Both halves were
wrong, and the owner ruled against them on 2026-08-13.**

`TODO.foundation/18:3-8`: the typed IR is built in this foundation,
because Issue #2 states it as the architecture. The deferral this plan
leaned on had already been withdrawn there as "our reasoning rather than
the author's instruction" — so we cited a position that no longer
existed.

What is true, and what item 04 is actually for:

- **Item 04 is a different boundary.** Scenes sit between layout and
  renderer and carry geometry. The IR sits between notation and layout
  and carries meaning. Item 04 kills the 24 undocumented hash shapes;
  that cost is real and is being paid on every corpus fix today. It does
  not discharge item 18.
- **Item 18 keeps its prerequisites**: after item 10, after item 14's
  `docs/emit-accept-survey.md`, after item 16's PlantUML class spike.
  That sequencing is what replaced the deferral — evidence before
  design.
- **One scheduling consequence.** This plan puts item 14 at item 08 step
  3. Item 18 can't start before 14's survey exists, so either 14 moves
  earlier or 18 lands after it. That decision is still open; it is
  flagged, not made.

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
  06, 07  corpus burndown    the METHOD stands; re-derive the per-type
                             denominators — theirs count artifacts
  08  lint, 109 live         small, can run any time
  11  docs truth             starts now, closes once the scoreboard exists
  14  elkrb + layout parity  adopted IN FULL, including the metric contract
  15  docs site build        independent
  17  release + versioning   independent
  18  typed IR               owner ruled it INTO this foundation
```

That is ten items, not seven — 06 and 07 share a line above.

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
  Layout::<Type>             every type, one per type
    |
  Scene              TYPED   where things GO          (geometry)
    |
  Renderer::<Type>           Scene -> Svg objects
    |
  one serializer             escapes once
    v
  SVG string
```

`Engine#render`'s core pipeline becomes four lines:

```ruby
type  = Notation::Mermaid.detect(source)
model = Parser.for(type).parse(source)
scene = Layout.for(type).call(model, theme: theme, today: today)
Renderer.for(type, theme: theme).render(scene)
```

Two rules hold it together:

- **No bare Hash crosses a layer boundary.** Every arrow is a class you
  can open and read.
- **Every type gets a Layout and a Scene.** An earlier draft deleted the
  two smallest — `Transform::InfoTransform` and
  `Transform::ErrorTransform`, 38 lines each — and handed the renderer
  the `Diagram` model. Withdrawn: `renderer/info.rb:71` reads
  `graph[:show_info]`, both renderers compute their own coordinates, and
  item 05's single document builder reads `width`/`height` off the
  Scene. They become the two smallest layouts instead, about twenty
  lines each. The pipeline has no optional-layout branch.

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
                                        explicitly temporary — item 06
                                        deletes it

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

**Deleted:** none on this count — the pass-through idea is withdrawn.
What an earlier draft would have deleted (`info`, `error`, maybe
`pie` — every other Transform computes geometry), 5 private palette
constants under 3 names (`DEFAULT_COLORS`, `FLOW_COLORS`,
`SECTION_COLORS`), 9 copies of `create_document_from_layout`, the no-op
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
  Layout::<Type>        where everything GOES             Diagram+Theme+Today -> Scene
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
agreed bar, so elkrb positions the eligible ones later. If the Scenes already
mirror what ELK emits, that's a swap; if we invent a different shape
now, it's a redesign.

**An ELK-shaped Scene is not a promise that elkrb will fill it.**
`sankey` is graph-shaped in the IR, roots its Scene on `nodes`, and
does its own layering; `block` is pre-positioned. Eligibility needs
`TODO.foundation/14`'s survey **and** a recorded, user-approved
exception for anything it excludes.

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
                                table at :27, the grid stub at :194,
                                the error wrapping at :114

  lib/sirena/transform/pie.rb   a "transform" that copies fields
  lib/sirena/transform/mindmap.rb  a "transform" that does layout
                                compare them and the naming problem
                                explains itself

  lib/sirena/renderer/pie.rb    then read the renderer that consumes
                                the hash pie.rb emits, and notice that
                                the contract only exists here

  lib/sirena/svg/text.rb        the same attribute declared twice —
                                `attribute` and a dead `map_attribute`
                                — plus one `writes_attributes` entry;
                                work out which one runs
```

Then pick one diagram type and trace a single `.mmd` file all the way
through to SVG. That's the hour that makes the rest of this document
obvious.
