# frozen_string_literal: true

# Reads the outline of a lone flowchart node of a given shape and size.
module FlowchartShapeProbe
  module_function

  def scene(shape, width, height)
    node = { id: "N", x: 0, y: 0, width: width, height: height,
             metadata: { shape: shape } }
    Sirena::Layout::Flowchart.from_graph(
      { id: "g", edges: [], children: [node] },
    )
  end

  def corner_radius(shape, width, height)
    scene(shape, width, height).children.first.corner_radius
  end

  # The rx of the rect the renderer draws for the node.
  def rendered_rx(shape, width, height)
    xml = Sirena::Renderer::Flowchart.new
      .render(scene(shape, width, height)).to_xml
    xml[/<rect[^>]*\brx="([\d.]+)"/, 1].to_f
  end

  # How far from the spine of a 14-point-long stadium of radius 18.5 a ray
  # of this direction leaves its outline, which should be that radius.
  def stadium_outline_distance(x_diff, y_diff)
    flowchart = Sirena::Layout::Flowchart.new
    scale = flowchart.send(:stadium_scale, 18.5, 25.5, x_diff, y_diff)
    spine_distance(scale * x_diff, scale * y_diff, 7.0)
  end

  def spine_distance(x_value, y_value, half_spine)
    Math.hypot(x_value, y_value - y_value.clamp(-half_spine, half_spine))
  end
end
