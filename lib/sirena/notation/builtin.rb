# frozen_string_literal: true

# Internal manifest: loads every built-in component and registers the
# Mermaid diagram types. Not public API; its contents may change in any release.

# Load modules in dependency order
require_relative "../js_number"
require_relative "../source"
require_relative "../text_measurement"
require_relative "../layout/grid"
require_relative "../diagram_registry"
require_relative "../theme"
require_relative "../theme/registry"
require_relative "../svg"
require_relative "../parser"
require_relative "../diagram"
require_relative "../layout"
require_relative "../renderer"
require_relative "../engine"

# Initialize theme registry with built-in themes
Sirena::Theme::Registry.load_builtin_themes

# Load and register flowchart handlers
require_relative "../parser/flowchart"
require_relative "../layout/flowchart"
require_relative "../renderer/flowchart"

Sirena::Notation::Mermaid.register_type(
  :flowchart,
  parser: Sirena::Parser::Flowchart,
  transform: Sirena::Layout::Flowchart,
  renderer: Sirena::Renderer::Flowchart,
  model: Sirena::Diagram::Flowchart,
)

# Load and register sequence diagram handlers
require_relative "../parser/sequence"
require_relative "../layout/sequence"
require_relative "../renderer/sequence"

Sirena::Notation::Mermaid.register_type(
  :sequence,
  parser: Sirena::Parser::Sequence,
  transform: Sirena::Layout::Sequence,
  renderer: Sirena::Renderer::Sequence,
  model: Sirena::Diagram::Sequence,
)

# Load and register class diagram handlers
require_relative "../parser/class_diagram"
require_relative "../layout/class_diagram"
require_relative "../renderer/class_diagram"

Sirena::Notation::Mermaid.register_type(
  :class_diagram,
  parser: Sirena::Parser::ClassDiagram,
  transform: Sirena::Layout::ClassDiagram,
  renderer: Sirena::Renderer::ClassDiagram,
  model: Sirena::Diagram::ClassDiagram,
)

# Load and register state diagram handlers
require_relative "../parser/state_diagram"
require_relative "../layout/state_diagram"
require_relative "../renderer/state_diagram"

Sirena::Notation::Mermaid.register_type(
  :state_diagram,
  parser: Sirena::Parser::StateDiagram,
  transform: Sirena::Layout::StateDiagram,
  renderer: Sirena::Renderer::StateDiagram,
  model: Sirena::Diagram::StateDiagram,
)

# Load and register ER diagram handlers
require_relative "../parser/er_diagram"
require_relative "../layout/er_diagram"
require_relative "../renderer/er_diagram"

Sirena::Notation::Mermaid.register_type(
  :er_diagram,
  parser: Sirena::Parser::ErDiagram,
  transform: Sirena::Layout::ErDiagram,
  renderer: Sirena::Renderer::ErDiagram,
  model: Sirena::Diagram::ErDiagram,
)

# Load and register user journey diagram handlers
require_relative "../parser/user_journey"
require_relative "../layout/user_journey"
require_relative "../renderer/user_journey"

Sirena::Notation::Mermaid.register_type(
  :user_journey,
  parser: Sirena::Parser::UserJourney,
  transform: Sirena::Layout::UserJourney,
  renderer: Sirena::Renderer::UserJourney,
  model: Sirena::Diagram::UserJourney,
)

# Load and register pie chart diagram handlers
require_relative "../parser/pie"
require_relative "../layout/pie"
require_relative "../renderer/pie"

Sirena::Notation::Mermaid.register_type(
  :pie,
  parser: Sirena::Parser::Pie,
  transform: Sirena::Layout::Pie,
  renderer: Sirena::Renderer::Pie,
  model: Sirena::Diagram::Pie,
)

# Load and register Gantt chart diagram handlers
require_relative "../parser/gantt"
require_relative "../layout/gantt"
require_relative "../renderer/gantt"

Sirena::Notation::Mermaid.register_type(
  :gantt,
  parser: Sirena::Parser::Gantt,
  transform: Sirena::Layout::Gantt,
  renderer: Sirena::Renderer::Gantt,
  model: Sirena::Diagram::Gantt,
)

# Load and register Timeline diagram handlers
require_relative "../parser/timeline"
require_relative "../layout/timeline"
require_relative "../renderer/timeline"

Sirena::Notation::Mermaid.register_type(
  :timeline,
  parser: Sirena::Parser::Timeline,
  transform: Sirena::Layout::Timeline,
  renderer: Sirena::Renderer::Timeline,
  model: Sirena::Diagram::Timeline,
)

# Load and register Quadrant chart diagram handlers
require_relative "../parser/quadrant"
require_relative "../layout/quadrant"
require_relative "../renderer/quadrant"

Sirena::Notation::Mermaid.register_type(
  :quadrant,
  parser: Sirena::Parser::Quadrant,
  transform: Sirena::Layout::Quadrant,
  renderer: Sirena::Renderer::Quadrant,
  model: Sirena::Diagram::Quadrant,
)

# Load and register Git Graph diagram handlers
require_relative "../parser/git_graph"
require_relative "../layout/git_graph"
require_relative "../renderer/git_graph"

Sirena::Notation::Mermaid.register_type(
  :git_graph,
  parser: Sirena::Parser::GitGraph,
  transform: Sirena::Layout::GitGraph,
  renderer: Sirena::Renderer::GitGraph,
  model: Sirena::Diagram::GitGraph,
)

# Load and register Mindmap diagram handlers
require_relative "../parser/mindmap"
require_relative "../layout/mindmap"
require_relative "../renderer/mindmap"

Sirena::Notation::Mermaid.register_type(
  :mindmap,
  parser: Sirena::Parser::Mindmap,
  transform: Sirena::Layout::Mindmap,
  renderer: Sirena::Renderer::Mindmap,
  model: Sirena::Diagram::Mindmap,
)

# Load and register Kanban diagram handlers
require_relative "../parser/kanban"
require_relative "../layout/kanban"
require_relative "../renderer/kanban"

Sirena::Notation::Mermaid.register_type(
  :kanban,
  parser: Sirena::Parser::Kanban,
  transform: Sirena::Layout::Kanban,
  renderer: Sirena::Renderer::Kanban,
  model: Sirena::Diagram::Kanban,
)

# Load and register Radar chart diagram handlers
require_relative "../parser/radar"
require_relative "../layout/radar"
require_relative "../renderer/radar"

Sirena::Notation::Mermaid.register_type(
  :radar,
  parser: Sirena::Parser::Radar,
  transform: Sirena::Layout::Radar,
  renderer: Sirena::Renderer::Radar,
  model: Sirena::Diagram::Radar,
)

# Load and register Block diagram handlers
require_relative "../parser/block"
require_relative "../layout/block"
require_relative "../renderer/block"

Sirena::Notation::Mermaid.register_type(
  :block,
  parser: Sirena::Parser::Block,
  transform: Sirena::Layout::Block,
  renderer: Sirena::Renderer::Block,
  model: Sirena::Diagram::Block,
)

# Load and register Requirement diagram handlers
require_relative "../parser/requirement"
require_relative "../layout/requirement"
require_relative "../renderer/requirement"

Sirena::Notation::Mermaid.register_type(
  :requirement,
  parser: Sirena::Parser::Requirement,
  transform: Sirena::Layout::Requirement,
  renderer: Sirena::Renderer::Requirement,
  model: Sirena::Diagram::Requirement,
)

# Load and register XY Chart diagram handlers
require_relative "../parser/xy_chart"
require_relative "../layout/xy_chart"
require_relative "../renderer/xy_chart"

Sirena::Notation::Mermaid.register_type(
  :xychart,
  parser: Sirena::Parser::XyChart,
  transform: Sirena::Layout::XyChart,
  renderer: Sirena::Renderer::XyChart,
  model: Sirena::Diagram::XyChart,
)

# Load and register Architecture diagram handlers
require_relative "../parser/architecture"
require_relative "../layout/architecture"
require_relative "../renderer/architecture"

Sirena::Notation::Mermaid.register_type(
  :architecture,
  parser: Sirena::Parser::Architecture,
  transform: Sirena::Layout::Architecture,
  renderer: Sirena::Renderer::Architecture,
  model: Sirena::Diagram::Architecture,
)

# Load and register Sankey diagram handlers
require_relative "../parser/sankey"
require_relative "../layout/sankey"
require_relative "../renderer/sankey"

Sirena::Notation::Mermaid.register_type(
  :sankey,
  parser: Sirena::Parser::Sankey,
  transform: Sirena::Layout::Sankey,
  renderer: Sirena::Renderer::Sankey,
  model: Sirena::Diagram::Sankey,
)
# Load and register Packet diagram handlers
require_relative "../parser/packet"
require_relative "../layout/packet"
require_relative "../renderer/packet"

Sirena::Notation::Mermaid.register_type(
  :packet,
  parser: Sirena::Parser::Packet,
  transform: Sirena::Layout::Packet,
  renderer: Sirena::Renderer::Packet,
  model: Sirena::Diagram::Packet,
)

# Load and register Treemap diagram handlers
require_relative "../parser/treemap"
require_relative "../layout/treemap"
require_relative "../renderer/treemap"

Sirena::Notation::Mermaid.register_type(
  :treemap,
  parser: Sirena::Parser::Treemap,
  transform: Sirena::Layout::Treemap,
  renderer: Sirena::Renderer::Treemap,
  model: Sirena::Diagram::Treemap,
)

# Load and register C4 diagram handlers
require_relative "../parser/c4"
require_relative "../layout/c4"
require_relative "../renderer/c4"

Sirena::Notation::Mermaid.register_type(
  :c4,
  parser: Sirena::Parser::C4,
  transform: Sirena::Layout::C4,
  renderer: Sirena::Renderer::C4,
  model: Sirena::Diagram::C4,
)

# Load and register Info diagram handlers
require_relative "../parser/info"
require_relative "../layout/info"
require_relative "../renderer/info"

Sirena::Notation::Mermaid.register_type(
  :info,
  parser: Sirena::Parser::Info,
  transform: Sirena::Layout::Info,
  renderer: Sirena::Renderer::Info,
  model: Sirena::Diagram::Info,
)

# Load and register Error diagram handlers
require_relative "../parser/error"
require_relative "../layout/error"
require_relative "../renderer/error"

Sirena::Notation::Mermaid.register_type(
  :error,
  parser: Sirena::Parser::Error,
  transform: Sirena::Layout::Error,
  renderer: Sirena::Renderer::Error,
  model: Sirena::Diagram::Error,
)
