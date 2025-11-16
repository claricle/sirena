# Sirena Architecture

## Overview

Sirena is a pure Ruby implementation of Mermaid diagram generation following
strict object-oriented principles with model-driven architecture. The system
transforms Mermaid syntax into SVG output through a pipeline of well-separated
components.

## Core Principles

1. **Model-Driven Design**: All data structures use `Lutaml::Model` classes
2. **MECE Separation**: Each component has mutually exclusive, collectively
   exhaustive responsibilities
3. **Register-Based**: Diagram types and renderers registered dynamically
4. **Open/Closed**: Extensible without modification via inheritance/composition
5. **Single Responsibility**: Each class handles one cohesive concern

## Processing Pipeline

```
Mermaid Syntax Input (String)
         │
         ▼
    ┌─────────┐
    │ Parser  │  Parslet Grammar → Transform → Parser
    └────┬────┘  (3-layer architecture)
         │
         ▼
   ┌───────────┐
   │ Diagram   │  Lutaml::Model AST
   │   Model   │  (Flowchart, Sequence, etc.)
   └─────┬─────┘
         │
         ▼
   ┌───────────┐
   │Transform  │  Diagram → Graph Conversion
   │  Layer    │
   └─────┬─────┘
         │
         ▼
   ┌───────────┐
   │  Elkrb    │  Layout Computation
   │  Layout   │  (Node positions, edge routes)
   └─────┬─────┘
         │
         ▼
   ┌───────────┐
   │    SVG    │  Graph → SVG Conversion
   │ Renderer  │
   └─────┬─────┘
         │
         ▼
   ┌───────────┐
   │    SVG    │  Lutaml::Model Structure
   │  Builder  │
   └─────┬─────┘
         │
         ▼
  SVG XML Output (String)
```

## Component Architecture

```
Sirena (Root Module)
    │
    ├── Engine (Orchestrator)
    │     │
    │     ├── coordinates overall flow
    │     ├── delegates to Parser
    │     ├── delegates to Transform
    │     └── delegates to Renderer
    │
    ├── Parser (Syntax Analysis - Parslet-based)
    │     │
    │     ├── Grammars (Parslet syntax rules)
    │     ├── Transforms (Parslet tree transformations)
    │     ├── Parsers (orchestrate Grammar → Transform)
    │     └── produces Diagram Models
    │
    ├── Diagram (Domain Models)
    │     │
    │     ├── Base (Abstract)
    │     ├── Flowchart
    │     ├── Sequence
    │     ├── ClassDiagram
    │     ├── StateDiagram
    │     ├── ErDiagram
    │     └── UserJourney
    │
    ├── Transform (Model Conversion)
    │     │
    │     ├── Base (Abstract)
    │     ├── FlowchartTransform
    │     ├── SequenceTransform
    │     ├── ClassDiagramTransform
    │     ├── StateDiagramTransform
    │     ├── ErDiagramTransform
    │     └── UserJourneyTransform
    │
    ├── Renderer (SVG Generation)
    │     │
    │     ├── Base (Abstract)
    │     ├── FlowchartRenderer
    │     ├── SequenceRenderer
    │     ├── ClassDiagramRenderer
    │     ├── StateDiagramRenderer
    │     ├── ErDiagramRenderer
    │     └── UserJourneyRenderer
    │
    ├── Svg (SVG Models)
    │     │
    │     ├── Document
    │     ├── Element
    │     ├── Group
    │     ├── Path
    │     ├── Text
    │     ├── Rect
    │     ├── Circle
    │     ├── Line
    │     ├── Polygon
    │     └── Style
    │
    ├── DiagramRegistry (Type Registration)
    │     │
    │     ├── register(type, parser, transform, renderer)
    │     └── get(type) -> handler triple
    │
    └── TextMeasurement (Dimension Calculation)
          │
          ├── measure_text(text, font_size) -> {width, height}
          └── character-based approximations
```

## Parslet-Based Parser Architecture

**All 11 implemented diagram types use Parslet exclusively** for parsing. The
legacy lexer-based approach has been fully deprecated (see
[`lib/sirena/parser/lexer.rb`](lib/sirena/parser/lexer.rb) deprecation notice).

### 3-Layer Parslet Architecture

Every parser follows a consistent 3-layer pattern:

```
┌─────────────────────────────────────────────┐
│  Layer 1: Grammar (Parslet::Parser)        │
│  ────────────────────────────────────       │
│  • Defines syntax rules using Parslet DSL  │
│  • Parses text into intermediate tree      │
│  • Returns Hash/Array structures           │
│                                             │
│  File: lib/sirena/parser/grammars/*.rb     │
└────────────┬────────────────────────────────┘
             │
             ▼ Intermediate tree (Hash/Array)
┌─────────────────────────────────────────────┐
│  Layer 2: Transform (Parslet::Transform)   │
│  ──────────────────────────────────────     │
│  • Converts intermediate tree to models    │
│  • Maps patterns to Diagram objects        │
│  • Returns structured Diagram models       │
│                                             │
│  File: lib/sirena/parser/transforms/*.rb   │
└────────────┬────────────────────────────────┘
             │
             ▼ Diagram models (Lutaml::Model)
┌─────────────────────────────────────────────┐
│  Layer 3: Parser (Orchestrator)            │
│  ────────────────────────────────────       │
│  • Combines Grammar + Transform            │
│  • Public API: parse(input) → Diagram      │
│  • Handles errors and edge cases           │
│                                             │
│  File: lib/sirena/parser/*.rb              │
└─────────────────────────────────────────────┘
```

### Benefits of Parslet Architecture

1. **Superior Error Messages**: Parslet provides detailed context and line
   numbers for syntax errors, making debugging much easier.

2. **Composability**: Grammar rules can be composed and reused across diagram
   types through the Common grammar module.

3. **Maintainability**: The 3-layer separation makes code easier to understand,
   test, and modify. ~80% code reduction achieved vs. lexer approach.

4. **Declarative Syntax**: Grammar rules are declarative and self-documenting,
   making the parser logic clear and concise.

5. **Type Safety**: Transform layer produces strongly-typed Lutaml::Model
   objects, catching errors early.

### Example: Flowchart Parser

```ruby
# Layer 1: Grammar (lib/sirena/parser/grammars/flowchart.rb)
class FlowchartGrammar < Parslet::Parser
  include Common  # Shared rules

  rule(:flowchart) do
    diagram_type >> nodes >> edges >> eof
  end

  rule(:node) do
    identifier >> (str('[') >> text >> str(']')).as(:shape)
  end
end

# Layer 2: Transform (lib/sirena/parser/transforms/flowchart.rb)
class FlowchartTransform < Parslet::Transform
  rule(node: simple(:id), shape: simple(:text)) do
    Diagram::Flowchart::Node.new(id: id, text: text)
  end
end

# Layer 3: Parser (lib/sirena/parser/flowchart.rb)
class FlowchartParser
  def initialize
    @grammar = Grammars::FlowchartGrammar.new
    @transform = Transforms::FlowchartTransform.new
  end

  def parse(input)
    tree = @grammar.parse(input)
    @transform.apply(tree)
  end
end
```

### Migration Summary

All 4 legacy lexer-based parsers have been successfully migrated to Parslet:

| Parser | Migration | Code Reduction | Week |
|--------|-----------|----------------|------|
| Flowchart | ✅ Complete | ~80% | Week 7 |
| Class Diagram | ✅ Complete | ~85% | Week 8 |
| ER Diagram | ✅ Complete | ~82% | Week 9 |
| State Diagram | ✅ Complete | ~78% | Week 10 |

All remaining 7 diagram types (Sequence, User Journey, Timeline, Git Graph,
Gantt, Pie, Mindmap, Quadrant) were built with Parslet from the start.

**Result**: 100% architectural consistency across all 11 diagram types.

## Data Flow Details

### 1. Parsing Phase (Parslet-based)

```
Mermaid Source
      │
      ▼
   Grammar.parse
   (Parslet rules)
      │
      ▼
 Intermediate Tree
  (Hash/Array)
      │
      ▼
  Transform.apply
  (Pattern matching)
      │
      ▼
   Diagram Model
   (Lutaml::Model)
```

The parser produces typed diagram models that fully represent the diagram
structure. Each diagram type has its own Grammar, Transform, and Parser classes
following the consistent 3-layer pattern.

### 2. Transform Phase

```
Diagram Model
      │
      ▼
Transform.to_graph
      │
      ├── Convert nodes to Elkrb::Graph::Node
      ├── Convert edges to Elkrb::Graph::Edge
      ├── Apply text measurement for dimensions
      └── Set layout options
      │
      ▼
  Elkrb Graph
```

The transform layer is responsible for:
- Converting diagram-specific structures to generic graph structures
- Calculating node dimensions based on content
- Mapping diagram relationships to graph edges
- Setting appropriate layout algorithm options

### 3. Layout Phase

```
Elkrb Graph
      │
      ▼
Elkrb::LayoutEngine.layout
      │
      ├── Select algorithm (layered, force, etc.)
      ├── Compute node positions
      ├── Route edge paths with bend points
      └── Position labels
      │
      ▼
Laid Out Graph
(with x, y coordinates)
```

This phase is fully delegated to elkrb, which handles all layout computation.

### 4. Rendering Phase

```
Laid Out Graph
      │
      ▼
Renderer.render
      │
      ├── Create SVG::Document
      ├── Add nodes as SVG shapes
      ├── Add edges as SVG paths
      ├── Add labels as SVG text
      └── Apply styles
      │
      ▼
  SVG Model
(Lutaml::Model)
      │
      ▼
SVG.to_xml
      │
      ▼
  SVG String
```

The renderer converts positioned graph elements into SVG graphic primitives.

## Class Responsibility Matrix

| Component | Responsibility | Dependencies |
|-----------|---------------|--------------|
| `Engine` | Orchestrate entire pipeline | Parser, Transform, Renderer |
| `Parser::Grammars::*` | Define Parslet syntax rules | Parslet, Common |
| `Parser::Transforms::*` | Transform parse trees | Parslet::Transform, Diagram models |
| `Parser::*` | Orchestrate Grammar+Transform | Grammars, Transforms |
| `Diagram::Base` | Abstract diagram model | Lutaml::Model |
| `Diagram::*` | Specific diagram structures | Diagram::Base |
| `Transform::Base` | Abstract graph converter | Elkrb |
| `Transform::*` | Diagram-specific conversion | Transform::Base, TextMeasurement |
| `Renderer::Base` | Abstract SVG renderer | Svg |
| `Renderer::*` | Diagram-specific rendering | Renderer::Base, Svg |
| `Svg::*` | SVG graphic primitives | Lutaml::Model, Moxml |
| `DiagramRegistry` | Type handler registration | None |
| `TextMeasurement` | Text dimension calculation | None |

**Note**: `Parser::Lexer` is deprecated and will be removed in v2.0.0. All
parsers now use the Parslet-based 3-layer architecture.

## Extensibility Points

### Adding New Diagram Types

```ruby
# 1. Define diagram model
class Diagram::NewType < Diagram::Base
  attribute :elements, :array
  # ... diagram-specific attributes
end

# 2. Implement transform
class Transform::NewTypeTransform < Transform::Base
  def to_graph(diagram)
    # Convert diagram to Elkrb::Graph
  end
end

# 3. Implement renderer
class Renderer::NewTypeRenderer < Renderer::Base
  def render(graph)
    # Convert graph to SVG
  end
end

# 4. Register
DiagramRegistry.register(
  :new_type,
  parser: Parser::NewTypeGrammar,
  transform: Transform::NewTypeTransform,
  renderer: Renderer::NewTypeRenderer
)
```

### Adding New SVG Shapes

```ruby
# Define new SVG element
class Svg::NewShape < Svg::Element
  attribute :custom_attr, :string

  xml do
    map_element "new-shape", to: :itself
    # ... XML mappings
  end
end
```

## SVG Builder Architecture

The SVG builder implements the complete SVG 1.2 graphic model using
Lutaml::Model. This enables:

1. **Object-Oriented SVG Construction**: Build SVG programmatically
2. **Type Safety**: Strong typing via Lutaml::Model attributes
3. **Serialization**: Automatic XML generation via Moxml
4. **Composability**: Nested element structures

```
SVG::Document
    │
    ├── viewBox: String
    ├── width: Numeric
    ├── height: Numeric
    └── children: Array<SVG::Element>
            │
            ├── SVG::Group
            │     ├── transform: String
            │     ├── style: SVG::Style
            │     └── children: Array<SVG::Element>
            │
            ├── SVG::Path
            │     ├── d: String (path data)
            │     └── style: SVG::Style
            │
            ├── SVG::Text
            │     ├── x, y: Numeric
            │     ├── content: String
            │     └── style: SVG::Style
            │
            └── SVG::Rect, Circle, Line, Polygon...
```

## Text Measurement Strategy

Text dimensions are calculated using character-based approximations:

```ruby
TextMeasurement.measure("Hello", font_size: 14)
# => { width: 35.0, height: 14.0 }

# Algorithm:
# - Average character width: font_size * 0.5
# - Height: font_size * 1.0
# - Width: char_count * avg_char_width
# - Users can override with explicit dimensions
```

This provides reasonable estimates for layout without requiring font metrics
libraries. Elkrb uses these dimensions for node sizing.

## Error Handling

```
Error (Base Exception)
   │
   ├── ParseError
   │     ├── LexerError
   │     └── GrammarError
   │
   ├── TransformError
   │     └── LayoutError
   │
   └── RenderError
         └── SvgBuildError
```

Each phase has specific error types for clear debugging and error reporting.

## Testing Strategy

### Unit Tests (Per Class)
- Each model class has structural tests
- Each parser component tests syntax handling
- Each transform tests graph conversion
- Each renderer tests SVG generation

### Integration Tests
- End-to-end: Mermaid syntax → SVG output
- Verify structural correctness of SVG
- Compare with expected fixture outputs
- Manual visual verification

### Fixtures
- Located in `spec/fixtures/`
- One subdirectory per diagram type
- Input `.mmd` files and expected outputs
- Cover edge cases and complex scenarios

## Directory Structure

```
sirena/
├── lib/
│   └── sirena/
│       ├── version.rb
│       ├── engine.rb
│       ├── diagram_registry.rb
│       ├── text_measurement.rb
│       ├── parser/
│       │   ├── base.rb
│       │   ├── lexer.rb (DEPRECATED - will be removed in v2.0.0)
│       │   ├── grammars/           # Parslet grammars (Layer 1)
│       │   │   ├── common.rb       # Shared grammar rules
│       │   │   ├── flowchart.rb
│       │   │   ├── class_diagram.rb
│       │   │   ├── er_diagram.rb
│       │   │   ├── state_diagram.rb
│       │   │   └── (other diagram grammars)
│       │   ├── transforms/         # Parslet transforms (Layer 2)
│       │   │   ├── flowchart.rb
│       │   │   ├── class_diagram.rb
│       │   │   ├── er_diagram.rb
│       │   │   ├── state_diagram.rb
│       │   │   └── (other diagram transforms)
│       │   ├── flowchart.rb        # Parser orchestrators (Layer 3)
│       │   ├── class_diagram.rb
│       │   ├── er_diagram.rb
│       │   ├── state_diagram.rb
│       │   └── (other diagram parsers)
│       ├── diagram/
│       │   ├── base.rb
│       │   ├── flowchart.rb
│       │   ├── sequence.rb
│       │   ├── class_diagram.rb
│       │   ├── state_diagram.rb
│       │   ├── er_diagram.rb
│       │   └── user_journey.rb
│       ├── transform/
│       │   ├── base.rb
│       │   └── (diagram-specific graph transforms)
│       ├── renderer/
│       │   ├── base.rb
│       │   └── (diagram-specific renderers)
│       ├── svg/
│       │   ├── document.rb
│       │   ├── element.rb
│       │   ├── group.rb
│       │   ├── path.rb
│       │   ├── text.rb
│       │   ├── rect.rb
│       │   ├── circle.rb
│       │   ├── line.rb
│       │   ├── polygon.rb
│       │   └── style.rb
│       └── cli.rb
├── spec/
│   ├── spec_helper.rb
│   ├── fixtures/
│   │   ├── flowchart/
│   │   ├── sequence/
│   │   ├── class_diagram/
│   │   ├── state_diagram/
│   │   ├── er_diagram/
│   │   └── user_journey/
│   └── (test files mirroring lib/)
└── examples/
    ├── flowchart_example.mmd
    ├── sequence_example.mmd
    └── (other diagram type examples)
```

**Note**: The 3-layer Parslet architecture (grammars/ + transforms/ + parsers)
is now standard across all diagram types.

## Component Interaction Sequence

### Example: Rendering a Flowchart

```
User calls: Sirena.render(mermaid_source)
                 │
                 ▼
            Engine.render
                 │
    ┌────────────┼────────────┐
    │            │            │
    ▼            ▼            ▼
  Parse      Transform     Render
    │            │            │
    │            │            │
Diagram.      Elkrb.      SVG.
Flowchart     Graph      Document
    │            │            │
    └────────────┴────────────┘
                 │
                 ▼
           SVG XML String
```

### Detailed Flow

1. **Engine receives mermaid source**
   - Detects diagram type from syntax prefix
   - Looks up handler in DiagramRegistry

2. **Parser processes syntax** (Parslet 3-layer architecture)
   - Grammar parses input using Parslet rules
   - Transform converts intermediate tree to Diagram model
   - Returns typed Diagram model (Lutaml::Model)

3. **Transform converts to graph**
   - Analyzes diagram structure
   - Creates Elkrb::Graph::Node for each diagram element
   - Creates Elkrb::Graph::Edge for relationships
   - Applies TextMeasurement for node dimensions
   - Sets layout algorithm and options

4. **Elkrb computes layout**
   - Runs selected algorithm (layered, force, etc.)
   - Calculates x, y coordinates for all nodes
   - Routes edges with bend points
   - Positions labels

5. **Renderer generates SVG**
   - Creates SVG::Document root
   - Adds SVG shapes for each node
   - Adds SVG paths for each edge
   - Adds SVG text for labels
   - Applies styling

6. **SVG Builder serializes**
   - Traverses SVG model tree
   - Generates XML using Moxml
   - Returns SVG 1.2 compliant string

## Key Design Patterns

### Registry Pattern (DiagramRegistry)

Allows dynamic registration and retrieval of diagram type handlers without
hardcoding type checks.

```ruby
DiagramRegistry.register(:flowchart, {
  parser: Parser::FlowchartGrammar,
  transform: Transform::FlowchartTransform,
  renderer: Renderer::FlowchartRenderer
})

handler = DiagramRegistry.get(:flowchart)
diagram = handler[:parser].parse(source)
```

### Strategy Pattern (Transform/Renderer)

Each diagram type has its own transformation and rendering strategy,
implementing a common interface.

```ruby
class Transform::Base
  def to_graph(diagram)
    raise NotImplementedError
  end
end

class Transform::FlowchartTransform < Transform::Base
  def to_graph(diagram)
    # Flowchart-specific conversion
  end
end
```

### Builder Pattern (SVG)

SVG construction uses the builder pattern through Lutaml::Model to create
complex nested structures programmatically.

```ruby
svg = Svg::Document.new(width: 800, height: 600).tap do |doc|
  doc.children << Svg::Group.new.tap do |group|
    group.children << Svg::Rect.new(x: 0, y: 0, width: 100, height: 50)
    group.children << Svg::Text.new(x: 50, y: 25, content: "Node")
  end
end
```

### Template Method Pattern (Base Classes)

Base classes define the algorithm structure, with subclasses providing
specific implementations.

```ruby
class Renderer::Base
  def render(graph)
    svg = create_document(graph)
    render_nodes(graph, svg)
    render_edges(graph, svg)
    render_labels(graph, svg)
    svg
  end

  def render_nodes(graph, svg)
    raise NotImplementedError
  end

  # ... other template methods
end
```

## Dependencies and Their Roles

- **parslet (~> 2.0)**: Parser construction framework for all diagram parsers
- **lutaml-model (~> 0.7)**: Serialization framework for all models
- **elkrb**: Graph layout computation engine
- **moxml**: XML/SVG serialization via Nokogiri
- **thor**: CLI framework

## Integration with Metanorma

Sirena produces SVG 1.2 compliant output that can be directly embedded in
Metanorma documents without post-processing. The SVG includes:

- Proper XML namespace declarations
- ViewBox for scalability
- Embedded styling (no external CSS dependencies)
- Standard-compliant path data
- UTF-8 text encoding

Integration point:

```ruby
# In Metanorma document processing
svg_output = Sirena.render(mermaid_diagram_source)
# Embed directly in document
```