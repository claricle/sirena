# Layer contracts

The architecture in one page. When you are unsure where a piece of code
belongs, the answer is here. The root `ARCHITECTURE.md` is stale — it
describes ELK layout that does not exist — and item 07 replaces it with
this.

## The pipeline

```
  source text
    |
  Notation::Mermaid          detect the type from the text
    |  Symbol
  Parser::<Type>             Grammar (Parslet) -> Builder
    |  Diagram::<Type>
  Layout::<Type>             geometry, given the theme's font metrics
    |  Layout::<Type>::Scene
  Renderer::<Type>           shapes and colours, given the theme
    |  Svg::Document
  Svg serializer             escape, emit
    v
  SVG string
```

## Who owns what

Each layer's job in one sentence. If you cannot describe a class this
way, it owns more than one thing (rule R7).

| Layer | Owns | In | Out |
|---|---|---|---|
| `Notation::Mermaid` | which diagram type a piece of text is | `String` | `Symbol` |
| `Parser::<Type>` | turning text into meaning | `String` | `Diagram::<Type>` |
| `Diagram::<Type>` | **what the diagram says** — semantics, no geometry | — | — |
| `Layout::<Type>` | **where everything goes** — geometry, no styling | `Diagram::<Type>`, `Theme`, reference date | `Scene` |
| `Layout::<Type>::Scene` | the computed geometry — coordinates, no meaning | — | — |
| `Renderer::<Type>` | shapes, colours, fonts | `Scene`, and `Theme` via its constructor | `Svg::Document` |
| `Svg::*` | valid, escaped XML | — | `String` |

Two boundaries are easy to get wrong:

- **Diagram holds no coordinates.** If you are tempted to put `x` on a
  `Diagram::FlowchartNode`, it belongs on the Scene node instead.
- **Renderer computes no coordinates.** If a renderer does arithmetic on
  positions or angles, that arithmetic belongs in the layout. The
  renderer places shapes; it does not decide where they go.

## Theme enters twice, for two different reasons

This is currently wrong in the code, and fixing it is part of item 04.

```
  Theme --> Layout      font metrics: how big is this text, so how big
                        is the box that must contain it

  Theme --> Renderer    colours, stroke widths, font family and size as
                        rendered
```

Today **no layout receives a theme.** Nine of the 24 size text anyway,
at a hardcoded 14: seven declare `DEFAULT_FONT_SIZE = 14`
(`transform/c4.rb:19`, `class_diagram`, `er_diagram`, `flowchart`,
`sequence`, `state_diagram`, `user_journey`) and two write the literal
inline (`transform/block.rb:148`, `transform/architecture.rb`). The
other 15 never measure text at all — which is its own bug, and it is
item 04's job to give them a layout that does.

Meanwhile `Renderer::Base#apply_theme_to_text` renders at
`theme.typography.font_size_normal`.

The built-in `high_contrast` theme sets `font_size_normal: 16.0`. So
under `--theme high_contrast`, every node is sized for 14pt text and
rendered at 16pt, and the text overflows its box. That is not a styling
bug; it is the theme failing to reach the layer that needs it.

**Rule: any measurement that affects size is a layout concern and needs
the theme. Any decision that affects appearance is a renderer concern
and needs the theme.** Both get it; neither guesses.

`TextMeasurement` is a service used by layouts, never by renderers.

## Scene coordinates are final

A Scene's `x` and `y` are the numbers the renderer writes into the SVG.
There is no origin attribute and no offset applied at render time.

Whatever framing a type needs — canvas padding, a title band — the
layout has already applied it. `Scene#width` and `#height` include it,
and every point inside is already shifted.

A renderer that adds a constant to a coordinate is a bug, not a style.

## Nothing mutates its input

- `Layout::Base#call(diagram, theme:, today:)` returns a new Scene, via the
  subclass's `#scene(diagram)`. It never writes to
  the diagram.
- `Renderer#render(scene)` returns a new document, and never writes to
  the scene. The theme reaches it through `Renderer.for(type, theme:)`,
  which is where a renderer already keeps it (`renderer/base.rb:42`).

Today `Engine#apply_fallback_layout` (`engine.rb:218`) mutates the graph
in place (`node.x = 50 + (col * 200)`) and returns the identical object it
was given. After item 03 that code is `Layout::Grid`.

**But item 03 declares itself a pure rename with zero logic change, so it
cannot also make Grid non-mutating** — those are two different items. The
mutation-to-replacement rewrite is a BEHAVIOUR change and belongs to a
behaviour-gated item (04, where Scene becomes the return value), not to
the rename. Item 03 moves this code and leaves its semantics alone.

This matters more than it looks: rendering the same diagram twice under
two themes must give two independent results, and item 08's comparator
renders the same input repeatedly.

## Error taxonomy

Each layer raises its own error, and the class survives to the caller.

| Layer | Raises |
|---|---|
| `Notation` | `Sirena::DiagramTypeError` |
| `Parser` | `Sirena::ParseError` |
| `Layout` | `Sirena::LayoutError` |
| `Renderer` | `Sirena::RenderError` |

All four inherit `Sirena::Error`.

**This is currently broken and item 01 fixes it before anything else.**
`Engine#render` collapses every non-detection failure into a single
`PipelineError` (`engine.rb:119-121`), with the backtrace concatenated
into the message string:

```ruby
rescue StandardError => e
  raise PipelineError, "Rendering failed: #{e.message}\n#{e.backtrace.join("\n")}"
```

Two consequences:

- **The corpus harness cannot tell a parse failure from a render
  failure**, so item 01's `stage` field — which `TODO.foundation/05`
  derives its entire work list from — would record `PipelineError` for
  everything except detection.
- A caller cannot rescue selectively, and the backtrace is stringified
  where a normal `cause` chain should be.
- **And it does not even catch everything.** `NotImplementedError`
  inherits `ScriptError`, not `StandardError`, so the six models that
  inherit `Diagram::Base#valid?` raise straight past this rescue. Item
  01 has the measurement.

Let each layer's error propagate. **`Engine#render` does not wrap** —
item 01 requires a failing parse to come out as `ParseError`, not
`PipelineError`, and that is the criterion the two documents agree on.

`PipelineError` survives only for a failure that belongs to no layer.
Where it is raised it goes inside a `rescue => e` so `e` remains the
`cause`, and it never stringifies a backtrace.

## What Renderer::Base owns, after item 05

Today it owns theme lookup, SVG path helpers, style factories and a
no-op `add_arrow_marker` placeholder (`renderer/base.rb:242`) — four
things and a stub.

Afterwards:

- document creation from `scene.width` / `scene.height`
- theme accessors, which **raise on a missing key** rather than
  returning `nil` for the caller to `||` past
- shared SVG helpers used by more than two renderers

`add_arrow_marker` is a placeholder that does nothing; delete it.

## Where a new file goes

| You are writing | It goes in |
|---|---|
| a syntax rule | `parser/grammars/<type>.rb` |
| parse tree to model | `parser/builders/<type>.rb` |
| a diagram concept | `diagram/<type>.rb` |
| a coordinate calculation | `layout/<type>.rb` |
| an SVG shape choice | `renderer/<type>.rb` |
| a colour | the theme YAML, never a renderer |
| a new diagram type | 8 files: `parser/<type>.rb`, its grammar and builder, `diagram/<type>.rb`, `layout/<type>.rb` (Scene inside), `renderer/<type>.rb`, `spec/fixtures/contract/<type>.mmd`, and one row in `TYPES`. Not the theme YAML — a new type adds no colours. `TODO.foundation/18` adds a row in `docs/ir-type-map.md`, and a notation-to-IR mapping whose home it has not settled — a new file makes 10, folding it into one of the eight keeps 9. Item 18 decides |
