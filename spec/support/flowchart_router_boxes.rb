# frozen_string_literal: true

# Laid-out boxes in the Hash shape Layout::FlowchartEdgeRouter reads.
module FlowchartRouterBoxes
  module_function

  def box(origin, size, metadata = {})
    { x: origin[0], y: origin[1], width: size[0], height: size[1],
      metadata: metadata }
  end

  def cluster(origin, size, extra = {})
    box(origin, size, { cluster: true }.merge(extra))
  end
end
