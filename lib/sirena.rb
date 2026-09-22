# frozen_string_literal: true

require_relative 'sirena/version'
require_relative 'sirena/error'
require_relative 'sirena/error_report'

module Sirena
  # Faults a hostile DOCUMENT can provoke that are not `StandardError`, so
  # every ordinary rescue in this gem -- and in any host embedding it --
  # lets them past and the process goes down.
  #
  # Derived rather than collected a name at a time: every `Exception`
  # descendant loaded in this process that is not a `StandardError` was
  # enumerated and classified, and exactly these two are exhaustion caused
  # by the source being rendered. The rest are Ruby's own control flow
  # (`SystemExit`, `SignalException`, `Timeout::ExitException`, `fatal`),
  # a broken install (`ScriptError` and its subclasses), or `SecurityError`
  # -- none of which mean "this diagram failed to render", and three of
  # which MUST reach the caller or `exit`, Ctrl-C and a host's
  # `Timeout.timeout` stop working. That is why this is an allowlist of two
  # and not a `rescue Exception` with a list of exemptions.
  #
  # `spec/sirena/exhaustion_errors_spec.rb` enumerates the loaded hierarchy
  # and holds this list against it in the two directions a machine can
  # decide: every name here really is outside `StandardError`, and no
  # control-flow class is here. Whether a NEW class is exhaustion is a
  # judgement Ruby exposes no marker for, so no spec can make that call --
  # adding one to this list is a human decision, taken here.
  EXHAUSTION_ERRORS = [SystemStackError, NoMemoryError].freeze

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
require_relative 'sirena/js_number'
require_relative 'sirena/source'
require_relative 'sirena/text_measurement'
require_relative 'sirena/layout/grid'
require_relative 'sirena/diagram_registry'
require_relative 'sirena/theme'
require_relative 'sirena/theme/registry'
require_relative 'sirena/svg'
require_relative 'sirena/parser'
require_relative 'sirena/diagram'
require_relative 'sirena/layout'
require_relative 'sirena/renderer'
require_relative 'sirena/engine'

# Initialize theme registry with built-in themes
Sirena::Theme::Registry.load_builtin_themes

# Load and register flowchart handlers
require_relative 'sirena/parser/flowchart'
require_relative 'sirena/layout/flowchart'
require_relative 'sirena/renderer/flowchart'

Sirena::DiagramRegistry.register(
  :flowchart,
  parser: Sirena::Parser::Flowchart,
  transform: Sirena::Layout::Flowchart,
  renderer: Sirena::Renderer::Flowchart,
  model: Sirena::Diagram::Flowchart
)

# Load and register sequence diagram handlers
require_relative 'sirena/parser/sequence'
require_relative 'sirena/layout/sequence'
require_relative 'sirena/renderer/sequence'

Sirena::DiagramRegistry.register(
  :sequence,
  parser: Sirena::Parser::Sequence,
  transform: Sirena::Layout::Sequence,
  renderer: Sirena::Renderer::Sequence,
  model: Sirena::Diagram::Sequence
)

# Load and register class diagram handlers
require_relative 'sirena/parser/class_diagram'
require_relative 'sirena/layout/class_diagram'
require_relative 'sirena/renderer/class_diagram'

Sirena::DiagramRegistry.register(
  :class_diagram,
  parser: Sirena::Parser::ClassDiagram,
  transform: Sirena::Layout::ClassDiagram,
  renderer: Sirena::Renderer::ClassDiagram,
  model: Sirena::Diagram::ClassDiagram
)

# Load and register state diagram handlers
require_relative 'sirena/parser/state_diagram'
require_relative 'sirena/layout/state_diagram'
require_relative 'sirena/renderer/state_diagram'

Sirena::DiagramRegistry.register(
  :state_diagram,
  parser: Sirena::Parser::StateDiagram,
  transform: Sirena::Layout::StateDiagram,
  renderer: Sirena::Renderer::StateDiagram,
  model: Sirena::Diagram::StateDiagram
)

# Load and register ER diagram handlers
require_relative 'sirena/parser/er_diagram'
require_relative 'sirena/layout/er_diagram'
require_relative 'sirena/renderer/er_diagram'

Sirena::DiagramRegistry.register(
  :er_diagram,
  parser: Sirena::Parser::ErDiagram,
  transform: Sirena::Layout::ErDiagram,
  renderer: Sirena::Renderer::ErDiagram,
  model: Sirena::Diagram::ErDiagram
)

# Load and register user journey diagram handlers
require_relative 'sirena/parser/user_journey'
require_relative 'sirena/layout/user_journey'
require_relative 'sirena/renderer/user_journey'

Sirena::DiagramRegistry.register(
  :user_journey,
  parser: Sirena::Parser::UserJourney,
  transform: Sirena::Layout::UserJourney,
  renderer: Sirena::Renderer::UserJourney,
  model: Sirena::Diagram::UserJourney
)

# Load and register pie chart diagram handlers
require_relative 'sirena/parser/pie'
require_relative 'sirena/layout/pie'
require_relative 'sirena/renderer/pie'

Sirena::DiagramRegistry.register(
  :pie,
  parser: Sirena::Parser::Pie,
  transform: Sirena::Layout::Pie,
  renderer: Sirena::Renderer::Pie,
  model: Sirena::Diagram::Pie
)

# Load and register Gantt chart diagram handlers
require_relative 'sirena/parser/gantt'
require_relative 'sirena/layout/gantt'
require_relative 'sirena/renderer/gantt'

Sirena::DiagramRegistry.register(
  :gantt,
  parser: Sirena::Parser::Gantt,
  transform: Sirena::Layout::Gantt,
  renderer: Sirena::Renderer::Gantt,
  model: Sirena::Diagram::Gantt
)

# Load and register Timeline diagram handlers
require_relative 'sirena/parser/timeline'
require_relative 'sirena/layout/timeline'
require_relative 'sirena/renderer/timeline'

Sirena::DiagramRegistry.register(
  :timeline,
  parser: Sirena::Parser::Timeline,
  transform: Sirena::Layout::Timeline,
  renderer: Sirena::Renderer::Timeline,
  model: Sirena::Diagram::Timeline
)

# Load and register Quadrant chart diagram handlers
require_relative 'sirena/parser/quadrant'
require_relative 'sirena/layout/quadrant'
require_relative 'sirena/renderer/quadrant'

Sirena::DiagramRegistry.register(
  :quadrant,
  parser: Sirena::Parser::Quadrant,
  transform: Sirena::Layout::Quadrant,
  renderer: Sirena::Renderer::Quadrant,
  model: Sirena::Diagram::Quadrant
)

# Load and register Git Graph diagram handlers
require_relative 'sirena/parser/git_graph'
require_relative 'sirena/layout/git_graph'
require_relative 'sirena/renderer/git_graph'

Sirena::DiagramRegistry.register(
  :git_graph,
  parser: Sirena::Parser::GitGraph,
  transform: Sirena::Layout::GitGraph,
  renderer: Sirena::Renderer::GitGraph,
  model: Sirena::Diagram::GitGraph
)

# Load and register Mindmap diagram handlers
require_relative 'sirena/parser/mindmap'
require_relative 'sirena/layout/mindmap'
require_relative 'sirena/renderer/mindmap'

Sirena::DiagramRegistry.register(
  :mindmap,
  parser: Sirena::Parser::Mindmap,
  transform: Sirena::Layout::Mindmap,
  renderer: Sirena::Renderer::Mindmap,
  model: Sirena::Diagram::Mindmap
)

# Load and register Kanban diagram handlers
require_relative 'sirena/parser/kanban'
require_relative 'sirena/layout/kanban'
require_relative 'sirena/renderer/kanban'

Sirena::DiagramRegistry.register(
  :kanban,
  parser: Sirena::Parser::Kanban,
  transform: Sirena::Layout::Kanban,
  renderer: Sirena::Renderer::Kanban,
  model: Sirena::Diagram::Kanban
)

# Load and register Radar chart diagram handlers
require_relative 'sirena/parser/radar'
require_relative 'sirena/layout/radar'
require_relative 'sirena/renderer/radar'

Sirena::DiagramRegistry.register(
  :radar,
  parser: Sirena::Parser::Radar,
  transform: Sirena::Layout::Radar,
  renderer: Sirena::Renderer::Radar,
  model: Sirena::Diagram::Radar
)

# Load and register Block diagram handlers
require_relative 'sirena/parser/block'
require_relative 'sirena/layout/block'
require_relative 'sirena/renderer/block'

Sirena::DiagramRegistry.register(
  :block,
  parser: Sirena::Parser::Block,
  transform: Sirena::Layout::Block,
  renderer: Sirena::Renderer::Block,
  model: Sirena::Diagram::Block
)


# Load and register Requirement diagram handlers
require_relative 'sirena/parser/requirement'
require_relative 'sirena/layout/requirement'
require_relative 'sirena/renderer/requirement'

Sirena::DiagramRegistry.register(
  :requirement,
  parser: Sirena::Parser::Requirement,
  transform: Sirena::Layout::Requirement,
  renderer: Sirena::Renderer::Requirement,
  model: Sirena::Diagram::Requirement
)

# Load and register XY Chart diagram handlers
require_relative 'sirena/parser/xy_chart'
require_relative 'sirena/layout/xy_chart'
require_relative 'sirena/renderer/xy_chart'

Sirena::DiagramRegistry.register(
  :xychart,
  parser: Sirena::Parser::XyChart,
  transform: Sirena::Layout::XyChart,
  renderer: Sirena::Renderer::XyChart,
  model: Sirena::Diagram::XyChart
)

# Load and register Architecture diagram handlers
require_relative 'sirena/parser/architecture'
require_relative 'sirena/layout/architecture'
require_relative 'sirena/renderer/architecture'

Sirena::DiagramRegistry.register(
  :architecture,
  parser: Sirena::Parser::Architecture,
  transform: Sirena::Layout::Architecture,
  renderer: Sirena::Renderer::Architecture,
  model: Sirena::Diagram::Architecture
)

# Load and register Sankey diagram handlers
require_relative 'sirena/parser/sankey'
require_relative 'sirena/layout/sankey'
require_relative 'sirena/renderer/sankey'

Sirena::DiagramRegistry.register(
  :sankey,
  parser: Sirena::Parser::Sankey,
  transform: Sirena::Layout::Sankey,
  renderer: Sirena::Renderer::Sankey,
  model: Sirena::Diagram::Sankey
)
# Load and register Packet diagram handlers
require_relative 'sirena/parser/packet'
require_relative 'sirena/layout/packet'
require_relative 'sirena/renderer/packet'

Sirena::DiagramRegistry.register(
  :packet,
  parser: Sirena::Parser::Packet,
  transform: Sirena::Layout::Packet,
  renderer: Sirena::Renderer::Packet,
  model: Sirena::Diagram::Packet
)

# Load and register Treemap diagram handlers
require_relative 'sirena/parser/treemap'
require_relative 'sirena/layout/treemap'
require_relative 'sirena/renderer/treemap'

Sirena::DiagramRegistry.register(
  :treemap,
  parser: Sirena::Parser::Treemap,
  transform: Sirena::Layout::Treemap,
  renderer: Sirena::Renderer::Treemap,
  model: Sirena::Diagram::Treemap
)

# Load and register C4 diagram handlers
require_relative 'sirena/parser/c4'
require_relative 'sirena/layout/c4'
require_relative 'sirena/renderer/c4'

Sirena::DiagramRegistry.register(
  :c4,
  parser: Sirena::Parser::C4,
  transform: Sirena::Layout::C4,
  renderer: Sirena::Renderer::C4,
  model: Sirena::Diagram::C4
)

# Load and register Info diagram handlers
require_relative 'sirena/parser/info'
require_relative 'sirena/layout/info'
require_relative 'sirena/renderer/info'

Sirena::DiagramRegistry.register(
  :info,
  parser: Sirena::Parser::Info,
  transform: Sirena::Layout::Info,
  renderer: Sirena::Renderer::Info,
  model: Sirena::Diagram::Info
)

# Load and register Error diagram handlers
require_relative 'sirena/parser/error'
require_relative 'sirena/layout/error'
require_relative 'sirena/renderer/error'

Sirena::DiagramRegistry.register(
  :error,
  parser: Sirena::Parser::Error,
  transform: Sirena::Layout::Error,
  renderer: Sirena::Renderer::Error,
  model: Sirena::Diagram::Error
)
