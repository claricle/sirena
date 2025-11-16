# frozen_string_literal: true

require_relative 'sirena/version'

module Sirena
  class Error < StandardError; end

  # Convenience method for rendering mermaid diagrams to SVG
  #
  # @param mermaid_source [String] Mermaid diagram source code
  # @param options [Hash] Rendering options
  # @return [String] SVG output
  def self.render(mermaid_source, options = {})
    Engine.new.render(mermaid_source, options)
  end
end

# Load modules in dependency order
require_relative 'sirena/text_measurement'
require_relative 'sirena/diagram_registry'
require_relative 'sirena/theme'
require_relative 'sirena/theme/registry'
require_relative 'sirena/svg'
require_relative 'sirena/parser'
require_relative 'sirena/diagram'
require_relative 'sirena/transform'
require_relative 'sirena/renderer'
require_relative 'sirena/engine'

# Initialize theme registry with built-in themes
Sirena::Theme::Registry.load_builtin_themes

# Convenience method for rendering mermaid diagrams to SVG
#
# @param mermaid_source [String] Mermaid diagram source code
# @param options [Hash] Rendering options
# @return [String] SVG output
def self.render(mermaid_source, options = {})
  Engine.new.render(mermaid_source, options)
end

# Load and register flowchart handlers
require_relative 'sirena/parser/flowchart'
require_relative 'sirena/transform/flowchart'
require_relative 'sirena/renderer/flowchart'

Sirena::DiagramRegistry.register(
  :flowchart,
  parser: Sirena::Parser::FlowchartParser,
  transform: Sirena::Transform::FlowchartTransform,
  renderer: Sirena::Renderer::FlowchartRenderer
)

# Load and register sequence diagram handlers
require_relative 'sirena/parser/sequence'
require_relative 'sirena/transform/sequence'
require_relative 'sirena/renderer/sequence'

Sirena::DiagramRegistry.register(
  :sequence,
  parser: Sirena::Parser::SequenceParser,
  transform: Sirena::Transform::SequenceTransform,
  renderer: Sirena::Renderer::SequenceRenderer
)

# Load and register class diagram handlers
require_relative 'sirena/parser/class_diagram'
require_relative 'sirena/transform/class_diagram'
require_relative 'sirena/renderer/class_diagram'

Sirena::DiagramRegistry.register(
  :class_diagram,
  parser: Sirena::Parser::ClassDiagramParser,
  transform: Sirena::Transform::ClassDiagramTransform,
  renderer: Sirena::Renderer::ClassDiagramRenderer
)

# Load and register state diagram handlers
require_relative 'sirena/parser/state_diagram'
require_relative 'sirena/transform/state_diagram'
require_relative 'sirena/renderer/state_diagram'

Sirena::DiagramRegistry.register(
  :state_diagram,
  parser: Sirena::Parser::StateDiagramParser,
  transform: Sirena::Transform::StateDiagramTransform,
  renderer: Sirena::Renderer::StateDiagramRenderer
)

# Load and register ER diagram handlers
require_relative 'sirena/parser/er_diagram'
require_relative 'sirena/transform/er_diagram'
require_relative 'sirena/renderer/er_diagram'

Sirena::DiagramRegistry.register(
  :er_diagram,
  parser: Sirena::Parser::ErDiagramParser,
  transform: Sirena::Transform::ErDiagramTransform,
  renderer: Sirena::Renderer::ErDiagramRenderer
)

# Load and register user journey diagram handlers
require_relative 'sirena/parser/user_journey'
require_relative 'sirena/transform/user_journey'
require_relative 'sirena/renderer/user_journey'

Sirena::DiagramRegistry.register(
  :user_journey,
  parser: Sirena::Parser::UserJourneyParser,
  transform: Sirena::Transform::UserJourneyTransform,
  renderer: Sirena::Renderer::UserJourneyRenderer
)

# Load and register pie chart diagram handlers
require_relative 'sirena/parser/pie'
require_relative 'sirena/transform/pie'
require_relative 'sirena/renderer/pie'

Sirena::DiagramRegistry.register(
  :pie,
  parser: Sirena::Parser::PieParser,
  transform: Sirena::Transform::PieTransform,
  renderer: Sirena::Renderer::PieRenderer
)

# Load and register Gantt chart diagram handlers
require_relative 'sirena/parser/gantt'
require_relative 'sirena/transform/gantt'
require_relative 'sirena/renderer/gantt'

Sirena::DiagramRegistry.register(
  :gantt,
  parser: Sirena::Parser::GanttParser,
  transform: Sirena::Transform::GanttTransform,
  renderer: Sirena::Renderer::GanttRenderer
)

# Load and register Timeline diagram handlers
require_relative 'sirena/parser/timeline'
require_relative 'sirena/transform/timeline'
require_relative 'sirena/renderer/timeline'

Sirena::DiagramRegistry.register(
  :timeline,
  parser: Sirena::Parser::TimelineParser,
  transform: Sirena::Transform::TimelineTransform,
  renderer: Sirena::Renderer::TimelineRenderer
)

# Load and register Quadrant chart diagram handlers
require_relative 'sirena/parser/quadrant'
require_relative 'sirena/transform/quadrant'
require_relative 'sirena/renderer/quadrant'

Sirena::DiagramRegistry.register(
  :quadrant,
  parser: Sirena::Parser::QuadrantParser,
  transform: Sirena::Transform::QuadrantTransform,
  renderer: Sirena::Renderer::QuadrantRenderer
)

# Load and register Git Graph diagram handlers
require_relative 'sirena/parser/git_graph'
require_relative 'sirena/transform/git_graph'
require_relative 'sirena/renderer/git_graph'

Sirena::DiagramRegistry.register(
  :git_graph,
  parser: Sirena::Parser::GitGraphParser,
  transform: Sirena::Transform::GitGraph,
  renderer: Sirena::Renderer::GitGraph
)

# Load and register Mindmap diagram handlers
require_relative 'sirena/parser/mindmap'
require_relative 'sirena/transform/mindmap'
require_relative 'sirena/renderer/mindmap'

Sirena::DiagramRegistry.register(
  :mindmap,
  parser: Sirena::Parser::MindmapParser,
  transform: Sirena::Transform::Mindmap,
  renderer: Sirena::Renderer::Mindmap
)

# Load and register Kanban diagram handlers
require_relative 'sirena/parser/kanban'
require_relative 'sirena/transform/kanban'
require_relative 'sirena/renderer/kanban'

Sirena::DiagramRegistry.register(
  :kanban,
  parser: Sirena::Parser::KanbanParser,
  transform: Sirena::Transform::Kanban,
  renderer: Sirena::Renderer::Kanban
)

# Load and register Radar chart diagram handlers
require_relative 'sirena/parser/radar'
require_relative 'sirena/transform/radar'
require_relative 'sirena/renderer/radar'

Sirena::DiagramRegistry.register(
  :radar,
  parser: Sirena::Parser::RadarParser,
  transform: Sirena::Transform::Radar,
  renderer: Sirena::Renderer::Radar
)

# Load and register Block diagram handlers
require_relative 'sirena/parser/block'
require_relative 'sirena/transform/block'
require_relative 'sirena/renderer/block'

Sirena::DiagramRegistry.register(
  :block,
  parser: Sirena::Parser::BlockParser,
  transform: Sirena::Transform::BlockTransform,
  renderer: Sirena::Renderer::BlockRenderer
)


# Load and register Requirement diagram handlers
require_relative 'sirena/parser/requirement'
require_relative 'sirena/transform/requirement'
require_relative 'sirena/renderer/requirement'

Sirena::DiagramRegistry.register(
  :requirement,
  parser: Sirena::Parser::RequirementParser,
  transform: Sirena::Transform::RequirementTransform,
  renderer: Sirena::Renderer::RequirementRenderer
)

# Load and register XY Chart diagram handlers
require_relative 'sirena/parser/xy_chart'
require_relative 'sirena/transform/xy_chart'
require_relative 'sirena/renderer/xy_chart'

Sirena::DiagramRegistry.register(
  :xychart,
  parser: Sirena::Parser::XYChartParser,
  transform: Sirena::Transform::XYChart,
  renderer: Sirena::Renderer::XYChart
)

# Load and register Architecture diagram handlers
require_relative 'sirena/parser/architecture'
require_relative 'sirena/transform/architecture'
require_relative 'sirena/renderer/architecture'

Sirena::DiagramRegistry.register(
  :architecture,
  parser: Sirena::Parser::Architecture,
  transform: Sirena::Transform::ArchitectureTransform,
  renderer: Sirena::Renderer::ArchitectureRenderer
)

# Load and register Sankey diagram handlers
require_relative 'sirena/parser/sankey'
require_relative 'sirena/transform/sankey'
require_relative 'sirena/renderer/sankey'

Sirena::DiagramRegistry.register(
  :sankey,
  parser: Sirena::Parser::SankeyParser,
  transform: Sirena::Transform::SankeyTransform,
  renderer: Sirena::Renderer::SankeyRenderer
)
# Load and register Packet diagram handlers
require_relative 'sirena/parser/packet'
require_relative 'sirena/transform/packet'
require_relative 'sirena/renderer/packet'

Sirena::DiagramRegistry.register(
  :packet,
  parser: Sirena::Parser::PacketParser,
  transform: Sirena::Transform::Packet,
  renderer: Sirena::Renderer::Packet
)

# Load and register Treemap diagram handlers
require_relative 'sirena/parser/treemap'
require_relative 'sirena/transform/treemap'
require_relative 'sirena/renderer/treemap'

Sirena::DiagramRegistry.register(
  :treemap,
  parser: Sirena::Parser::TreemapParser,
  transform: Sirena::Transform::Treemap,
  renderer: Sirena::Renderer::Treemap
)

# Load and register C4 diagram handlers
require_relative 'sirena/parser/c4'
require_relative 'sirena/transform/c4'
require_relative 'sirena/renderer/c4'

Sirena::DiagramRegistry.register(
  :c4,
  parser: Sirena::Parser::C4Parser,
  transform: Sirena::Transform::C4Transform,
  renderer: Sirena::Renderer::C4Renderer
)

# Load and register Info diagram handlers
require_relative 'sirena/parser/info'
require_relative 'sirena/transform/info'
require_relative 'sirena/renderer/info'

Sirena::DiagramRegistry.register(
  :info,
  parser: Sirena::Parser::InfoParser,
  transform: Sirena::Transform::InfoTransform,
  renderer: Sirena::Renderer::InfoRenderer
)

# Load and register Error diagram handlers
require_relative 'sirena/parser/error'
require_relative 'sirena/transform/error'
require_relative 'sirena/renderer/error'

Sirena::DiagramRegistry.register(
  :error,
  parser: Sirena::Parser::ErrorParser,
  transform: Sirena::Transform::ErrorTransform,
  renderer: Sirena::Renderer::ErrorRenderer
)
