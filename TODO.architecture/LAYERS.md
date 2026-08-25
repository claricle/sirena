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
| `Layout::<Type>` | **where everything goes** — geometry, no styling | `Diagram::<Type>`, `Theme` | `Scene` |
| `Layout::<Type>::Scene` | the computed geometry — coordinates, no meaning | — | — |
| `Renderer::<Type>` | shapes, colours, fonts | `Scene`, `Theme` | `Svg::Document` |
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

Today **no layout receives a theme.** Every one hardcodes
`DEFAULT_FONT_SIZE = 14` (`transform/er_diagram.rb:20`,
`transform/c4.rb:19`, `transform/block.rb:148`, and so on) while
`Renderer::Base#apply_theme_to_text` renders at
`theme.typography.font_size_normal`.

The built-in `high_contrast` theme sets `font_size_normal: 16.0`. So
under `--theme high_contrast`, every node is sized for 14pt text and
rendered at 16pt, and the text overflows its box. That is not a styling
bug; it is the theme failing to reach the layer that needs it.

**Rule: any measurement that affects size is a layout concern and needs
the theme. Any decision that affects appearance is a renderer concern
and needs the theme.** Both get it; neither guesses.

`TextMeasurement` is a service used by layouts, never by renderers.

## Nothing mutates its input

- `Layout#call(diagram, theme:)` returns a new Scene. It never writes to
  the diagram.
- `Renderer#render(scene, theme:)` returns a new document. It never
  writes to the scene.

Today `Engine#apply_fallback_layout` mutates the graph in place
(`node.x = 50 + (col * 200)`). After item 03 that code is
`Layout::Grid`, and it returns rather than mutates.

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
`PipelineError`, with the backtrace concatenated into the message
string:

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

Let each layer's error propagate. If the engine wraps at all, it wraps
with `raise PipelineError, msg` inside a `rescue => e` so `e` remains the
`cause`, and it never stringifies a backtrace.

## What Renderer::Base owns, after item 05

Today it owns theme lookup, SVG path helpers, style factories and a
no-op `add_arrow_marker` placeholder — four things and a stub.

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
| a new diagram type | all of the above, plus one row in `TYPES` |
