# frozen_string_literal: true

# Short builders for the IR graphs the layout coverage specs feed in.
module LayoutIrShorthand
  def ir_node(**attributes)
    Sirena::IR::Node.new(**attributes)
  end

  def ir_edge(**attributes)
    Sirena::IR::Edge.new(**attributes)
  end

  def ir_graph(nodes:, edges: [], **attributes)
    Sirena::IR::Graph.new(nodes: nodes, edges: edges, **attributes)
  end

  def ir_weight(value)
    Sirena::IR::PropertySet.new(weight: value)
  end
end
