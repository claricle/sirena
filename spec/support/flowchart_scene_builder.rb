# frozen_string_literal: true

# Lays out small flowcharts of rect nodes for the flowchart layout specs.
module FlowchartSceneBuilder
  BOX_ATTRIBUTES = %w[x y width height].freeze

  module_function

  # @param links [Array<Array>] [from, to] or [from, to, label]
  # @param labels [Hash] node id => label, for nodes not labelled by their id
  # @return [Sirena::Layout::Flowchart::Scene]
  def scene(direction, links, labels: {})
    Sirena::Layout::Flowchart.new.to_graph(diagram(direction, links, labels))
  end

  def diagram(direction, links, labels)
    diagram = Sirena::Diagram::Flowchart.new(direction: direction)
    ids = links.flat_map { |from, to, _| [from, to] }.uniq
    diagram.nodes.concat(ids.map { |id| rect(id, labels.fetch(id, id)) })
    diagram.edges.concat(links.map { |from, to, label| link(from, to, label) })
    diagram
  end

  # @return [Hash{String => Object}] the laid-out nodes by id
  def placed(direction, links, labels: {})
    scene(direction, links, labels: labels).children
      .to_h { |node| [node.id, node] }
  end

  # The one laid-out node of a flowchart holding only it.
  def lone_node(shape, label)
    diagram = Sirena::Diagram::Flowchart.new(direction: "TD")
    diagram.nodes << Sirena::Diagram::FlowchartNode.new(
      id: "A", label: label, shape: shape,
    )
    Sirena::Layout::Flowchart.new.to_graph(diagram).children.first
  end

  # The free space from one node to the next along :x or :y.
  def clearance(from, to, axis)
    size = axis == :x ? :width : :height
    to.public_send(axis) - (from.public_send(axis) + from.public_send(size))
  end

  # The free space between the nodes with these ids in a laid-out scene.
  def gap(scene, from_id, to_id, axis)
    nodes = scene.children.to_h { |node| [node.id, node] }
    clearance(nodes[from_id], nodes[to_id], axis)
  end

  # How far a flowchart's one subgraph box sits outside the boxes it
  # holds, as [left, right, top, bottom], read off the rendered SVG.
  def cluster_margins(source)
    rects = Sirena::Engine.new.render(source).scan(/<rect[^>]*>/).map do |tag|
      BOX_ATTRIBUTES.map { |name| tag[/\s#{name}="(-?[\d.]+)"/, 1].to_f }
    end
    cluster = rects.max_by { |_, _, width, height| width * height }
    inner = rects.reject { |rect| rect == cluster }
    margins(cluster, inner)
  end

  def margins(cluster, inner)
    held = hull(inner)
    outer = sides(cluster)
    [held[0] - outer[0], outer[2] - held[2],
     held[1] - outer[1], outer[3] - held[3]]
  end

  # The [left, top, right, bottom] of the smallest box around the rectangles.
  def hull(rects)
    lefts, tops, rights, bottoms = rects.map { |rect| sides(rect) }.transpose
    [lefts.min, tops.min, rights.max, bottoms.max]
  end

  # [left, top, right, bottom] of an [x, y, width, height] rectangle.
  def sides(rect)
    x, y, width, height = rect
    [x, y, x + width, y + height]
  end

  def rect(id, label)
    Sirena::Diagram::FlowchartNode.new(id: id, label: label, shape: "rect")
  end

  def link(from, to, label)
    Sirena::Diagram::FlowchartEdge.new(
      source_id: from, target_id: to, arrow_type: "arrow", label: label,
    )
  end
end
