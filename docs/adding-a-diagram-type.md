# Adding a diagram type

Adding a Mermaid diagram type to Sirena touches eight files. One command
writes all of them, plus their specs. This page says what each file owns,
walks through adding a trivial type called `demo`, and ends with the table
for fixing a failing corpus case.

Every command below was run on a clean checkout; the output shown is what
it printed.

## The pipeline

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

## The eight files

```
  lib/sirena/parser/<type>.rb             the parser itself
  lib/sirena/parser/grammars/<type>.rb    what the text LOOKS LIKE
  lib/sirena/parser/builders/<type>.rb    parse tree -> model
  lib/sirena/diagram/<type>.rb            what the diagram MEANS
  lib/sirena/layout/<type>.rb             geometry, AND its Scene class
  lib/sirena/renderer/<type>.rb           scene -> SVG
  spec/fixtures/contract/<type>.mmd       the contract fixture
  lib/sirena/notation/mermaid.rb          one row in TYPES
```

- **Parser** wires one grammar to one builder; it has no logic of its own.
- **Grammar** is a Parslet grammar that accepts or rejects the text and
  produces a raw parse tree.
- **Builder** turns that tree into the typed model.
- **Diagram** is the typed model: what the text means, with no geometry.
- **Layout** turns the model into positions and sizes. Its `Scene` class
  lives in the same file.
- **Renderer** draws a `Scene` as SVG objects, using the theme.
- **Contract fixture** is the one canonical source the shared examples
  parse, lay out and render.
- **`TYPES` row** is the keyword pattern that makes detection pick your type.

Every type has a layout, even one with trivial geometry.

## The generator

Quote the task. Unquoted brackets die in zsh.

```sh
bundle exec rake 'type:new[demo]'
```

It prints the paths it wrote, the eight files plus four specs:

```
lib/sirena/parser/demo.rb
lib/sirena/parser/grammars/demo.rb
lib/sirena/parser/builders/demo.rb
lib/sirena/diagram/demo.rb
lib/sirena/layout/demo.rb
lib/sirena/renderer/demo.rb
spec/fixtures/contract/demo.mmd
spec/sirena/parser/demo_spec.rb
spec/sirena/diagram/demo_spec.rb
spec/sirena/layout/demo_spec.rb
spec/sirena/renderer/demo_spec.rb
lib/sirena/notation/mermaid.rb
```

It refuses, and writes nothing, when the name is not `snake_case`, the
type is already registered, an earlier `TYPES` row already claims the
keyword, or any target file already exists. The keyword is the type name.

## Worked example: `demo`

`demo` is a list: the keyword, then one item per indented line.

```
demo
  first
  second
```

That is `spec/fixtures/contract/demo.mmd`, as generated.

Run the contract examples and the four generated specs. No hand-editing
is needed for either to pass:

```sh
bundle exec rspec spec/contract_spec.rb -e demo
bundle exec rspec spec/sirena/parser/demo_spec.rb \
  spec/sirena/diagram/demo_spec.rb spec/sirena/layout/demo_spec.rb \
  spec/sirena/renderer/demo_spec.rb
```

```
12 examples, 0 failures
9 examples, 0 failures
```

Render it:

```sh
bundle exec exe/sirena render spec/fixtures/contract/demo.mmd -o demo.svg
```

```
<svg
 width="300.0"
 height="100.0"
 viewBox="0 0 300 100"
 version="1.2"
 baseProfile="tiny"
 xmlns="http://www.w3.org/2000/svg"
>
<text fill="#000000" x="20.0" y="35.0" font-family="Arial, Helvetica, sans-serif" font-size="14.0">first</text>
<text fill="#000000" x="20.0" y="65.0" font-family="Arial, Helvetica, sans-serif" font-size="14.0">second</text>
</svg>
```

(`demo.svg` holds that SVG; the command itself prints nothing.)

From here you change the generated files to make `demo` mean something:
grammar for the syntax, builder and diagram for the model, layout for the
geometry, renderer for the drawing. Run the same specs after each change.

## Corpus: one type at a time

`spec/mermaid/<type>/` holds cases extracted from the mermaid-js suite.
Quote the task here too:

```sh
bundle exec rake 'corpus[pie]'
```

```
corpus[pie]: 49/49 cases render (100.0%)
  against evidence-valid cases only: 40/40 = 100.0%

failing:
  none
```

This is diagnostic only: it does not write `scoreboard/corpus.json`. The
only filter is `valid`, which lists failures the oracle calls valid:

```sh
bundle exec rake 'corpus[pie,valid]'
```

Any other filter aborts with `Unknown corpus filter ... the only filter
is "valid"`. Each failing case prints one line: path, stage, oracle
verdict, first line of the error.

```
failing:
  flowchart/007_platform_current_flowchart_6.mmd  parse  invalid  Parse error at line 1, column 14:
```

(The path column is padded to the widest case and the line is shortened
here.) Rows are sorted by stage, then path.

## How do I fix a failing case?

Read the stage column, then open the file:

| stage | what it means | file to open |
|---|---|---|
| `detect` | no type matched the source | `lib/sirena/notation/mermaid.rb`, the `TYPES` row |
| `parse` | the grammar rejected the text (`Parse error at line N, column M`) | `lib/sirena/parser/grammars/<type>.rb` |
| `parse` | no position in the message: the grammar accepted it, the model build failed | `lib/sirena/parser/builders/<type>.rb` |
| `layout` | geometry raised | `lib/sirena/layout/<type>.rb` |
| `render` | SVG generation raised | `lib/sirena/renderer/<type>.rb` |

The stage column can also read `timeout` (a case ran past the per-case
limit) or `unknown` (an exception that belongs to no layer); neither has
a fixed file, so reproduce it with the command below.

To see the full error for one case:

```sh
bundle exec exe/sirena render spec/mermaid/flowchart/007_platform_current_flowchart_6.mmd -o /dev/null
```

```
Error: Parse error at line 1, column 14:
flowchart BT subgraph S1 sub1 -->sub2 end subgraph S2 sub4 end S1 --> S2 sub1 --> sub4
             ^
Expected "\n", but got "s"
```

It exits 1. When the case passes, `corpus[<type>]` no longer lists it. A
fix that turns a case green must also update `scoreboard/corpus.json`
(`rake corpus`), or `rake corpus:check` reports it as an unrecorded
improvement.
