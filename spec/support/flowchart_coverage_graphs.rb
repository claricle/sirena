# frozen_string_literal: true

# Hand-positioned ELK-shaped graphs for Layout::Flowchart.from_graph.
module FlowchartCoverageGraphs
  module_function

  def node(name, origin, size = [100, 50], shape = "rect")
    { id: name, x: origin[0], y: origin[1], width: size[0],
      height: size[1], labels: [{ text: name }],
      metadata: { shape: shape } }
  end

  def edge(name, source, target, arrow = "arrow")
    { id: name, sources: [source], targets: [target],
      metadata: { arrow_type: arrow } }
  end

  def scene(children, edges, direction = nil)
    options = direction ? { "elk.direction" => direction } : {}
    Sirena::Layout::Flowchart.from_graph(
      { id: "g", children: children, edges: edges, layoutOptions: options },
    )
  end

  SETTING_ROLES = %w[diagram_settings diagram_identifier layout_direction
                     theme_reference].freeze

  # The adapter output, with its settings nodes dropped unless keep is set.
  def settingless_graph(source, keep: false)
    ir = Sirena::Notation::Mermaid::IRAdapters::Flowchart.call(
      Sirena::Parser::Flowchart.new.parse(source),
    )
    return ir if keep

    kept = ir.nodes.reject { |item| SETTING_ROLES.include?(item.role) }
    Sirena::IR::Graph.new(id: ir.id, nodes: kept, edges: ir.edges)
  end
end
