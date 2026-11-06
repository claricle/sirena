# frozen_string_literal: true

# Where the marks of an activity scene lie, for specs that check edges and
# labels against the nodes and each other.
module SceneGeometry
  ANCHOR_SHARE = { "start" => 0, "middle" => 0.5, "end" => 1 }.freeze
  SLACK = 1.0

  Rect = Struct.new(:left, :top, :width, :height) do
    def right
      left + width
    end

    def bottom
      top + height
    end

    def overlaps?(other)
      left < other.right && other.left < right &&
        top < other.bottom && other.top < bottom
    end

    def near?(x_pos, y_pos)
      x_pos.between?(left - SLACK, right + SLACK) &&
        y_pos.between?(top - SLACK, bottom + SLACK)
    end

    def border?(point)
      x_pos, y_pos = point
      near?(x_pos, y_pos) && (beside?(x_pos, [left, right]) ||
                              beside?(y_pos, [top, bottom]))
    end

    def beside?(value, edges)
      edges.any? { |edge| (value - edge).abs <= SLACK }
    end
  end

  def node_boxes(scene)
    scene.marks.filter_map { |mark| node_box(mark) }
  end

  def node_box(mark)
    attrs = mark.attrs
    case mark.kind
    when :rect then Rect.new(*attrs.values_at(:x, :y, :width, :height))
    when :circle then circle_box(attrs)
    when :polygon then diamond_box(attrs[:points])
    end
  end

  def circle_box(attrs)
    radius = attrs[:r]
    Rect.new(attrs[:cx] - radius, attrs[:cy] - radius, 2 * radius, 2 * radius)
  end

  # Arrowheads are triangles; only a diamond has four corners.
  def diamond_box(points)
    return unless points.size == 4

    xs, ys = points.transpose
    Rect.new(xs.min, ys.min, xs.max - xs.min, ys.max - ys.min)
  end

  # @return [Array<Mark>] the paths whose end touches no node
  def dangling_edges(scene)
    boxes = node_boxes(scene)
    scene.marks.select { |m| m.kind == :path }.reject do |mark|
      boxes.any? { |box| box.border?(mark.attrs[:points].last) }
    end
  end

  def label_boxes(scene)
    metrics = Sirena::Notation::PlantUML::Activity::Metrics.new
    scene.marks.select { |m| m.kind == :text }.map do |mark|
      label_box(metrics, mark.attrs)
    end
  end

  def label_box(metrics, attrs)
    width = metrics.text_width([attrs[:content]], role: :arrow,
                                                  size: attrs[:size])
    left = attrs[:x] - (width * ANCHOR_SHARE.fetch(attrs[:anchor]))
    Rect.new(left, attrs[:y] - attrs[:size], width, attrs[:size])
  end
end
