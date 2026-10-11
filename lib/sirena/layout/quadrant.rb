# frozen_string_literal: true

require_relative "base"
require_relative "../notation/mermaid/ir_adapters/quadrant"

module Sirena
  module Layout
    # Builds final quadrant-chart geometry.
    class Quadrant < Base
      # mmdc's quadrantChart defaults (mermaid quadrantBuilder.ts).
      CHART_SIZE = 500
      PADDING = 5
      AXIS_LABEL_PADDING = 5
      QUADRANT_TEXT_TOP_PADDING = 5
      TITLE_PADDING = 10
      POINT_TEXT_PADDING = 5
      EXTERNAL_BORDER = 2
      INTERNAL_BORDER = 1
      HALF_BORDER = EXTERNAL_BORDER / 2.0
      PLOT_SIZE = CHART_SIZE - (2 * PADDING)

      # The plotted area inside the chart's padding, axes and title.
      Space = Data.define(:left, :top, :width, :height, :title, :x_axis,
                          :x_axis_below) do
        def half_width = width / 2.0
        def half_height = height / 2.0
        def right = left + width
        def bottom = top + height
        def mid_x = left + half_width
        def mid_y = top + half_height
        def across(grow) = [left - grow, right + grow]
        def down(grow) = [top - grow, bottom + grow]
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :text_anchor, :string
        attribute :font_weight, :string
        attribute :style, :string
        attribute :rotation, :float
        attribute :baseline, :string
      end

      class Rect < Lutaml::Model::Serializable
        attribute :number, :integer
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :label, Label
      end

      class Line < Lutaml::Model::Serializable
        attribute :x1, :float
        attribute :y1, :float
        attribute :x2, :float
        attribute :y2, :float
        attribute :stroke_width, :float
      end

      class Point < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :x, :float
        attribute :y, :float
        attribute :radius, :float
        attribute :quadrant, :integer
        attribute :color, :string
        attribute :stroke_color, :string
        attribute :stroke_width, :float
        attribute :label, Label
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :title, Label
        attribute :quadrants, Rect, collection: true, default: -> { [] }
        attribute :axes, Line, collection: true, default: -> { [] }
        attribute :axis_labels, Label, collection: true, default: -> { [] }
        attribute :quadrant_labels, Label, collection: true, default: -> { [] }
        attribute :points, Point, collection: true, default: -> { [] }
      end

      # Retains the pre-Scene structure for direct callers during conversion.
      def build_graph(diagram)
        data = ir_document(diagram)
        space = chart_space(data)
        {
          id: data.id, title: data.label, space: space,
          axes: axes(data),
          quadrants: quadrants(data, space),
          points: transform_points(data, space)
        }
      end

      private

      def scene(diagram)
        graph = build_graph(diagram)
        Scene.new(
          id: graph[:id], width: CHART_SIZE, height: CHART_SIZE,
          view_box: "0 0 #{CHART_SIZE} #{CHART_SIZE}",
          **scene_data(graph)
        )
      end

      def scene_data(graph)
        space = graph[:space]
        labels = quadrant_labels_by_number(graph[:quadrants], graph[:points])
        {
          title: title_label(graph[:title]),
          quadrants: typed_quadrants(graph[:quadrants], labels),
          axes: border_lines(space),
          axis_labels: axis_labels(graph[:axes], space),
          quadrant_labels: labels.values,
          points: typed_points(graph[:points]),
        }
      end

      def chart_space(data)
        title = title_space(data)
        x_room, y_room = axis_rooms(axes(data))
        below = points?(data)
        Space.new(
          left: PADDING + y_room, top: PADDING + (below ? 0 : x_room) + title,
          width: PLOT_SIZE - y_room, height: PLOT_SIZE - x_room - title,
          title: title, x_axis: x_room.positive?, x_axis_below: below
        )
      end

      # Room taken beside the plot by the x axis labels, then the y axis
      # labels; zero for an axis with no label written.
      def axis_rooms(axes)
        [axis_room(axes, :x_left, :x_right), axis_room(axes, :y_bottom, :y_top)]
      end

      def axis_room(axes, first, second)
        return 0 if axes.values_at(first, second).all?(&:empty?)

        (2 * AXIS_LABEL_PADDING) + large_font_size
      end

      def title_space(data)
        return 0 if data.label.to_s.empty?

        title_font_size + (2 * TITLE_PADDING)
      end

      def points?(data)
        data.items.any? { |item| item.role == "point" }
      end

      def ir_document(diagram)
        return diagram if diagram.is_a?(IR::Prepositioned)

        Notation::Mermaid::IRAdapters::Quadrant.call(diagram)
      end

      def axes(data)
        labels = axis_labels_for(data)
        { x_left: labels["x_min"] || "", x_right: labels["x_max"] || "",
          y_bottom: labels["y_min"] || "", y_top: labels["y_max"] || "" }
      end

      def axis_labels_for(data)
        data.items.select { |item| item.role == "axis_label" }
          .to_h { |item| [placement_value(item, "axis_position"), item.label] }
      end

      def quadrants(data, space)
        labels = data.items.select { |item| item.role == "region_label" }
          .to_h { |item| [placement_value(item, "region").to_i, item.label] }
        (1..4).to_h do |number|
          [:"q#{number}", {
            label: labels[number], number: number,
            bounds: quadrant_bounds(number, space)
          }]
        end
      end

      def quadrant_bounds(number, space)
        x = [1, 4].include?(number) ? space.left + space.half_width : space.left
        y = [3, 4].include?(number) ? space.top + space.half_height : space.top
        { x: x, y: y, width: space.half_width, height: space.half_height }
      end

      def title_label(title)
        return if title.to_s.empty?

        label(title, [CHART_SIZE / 2.0, TITLE_PADDING], title_font_size,
              "title", anchor: "middle", baseline: "hanging")
      end

      def typed_quadrants(quadrants, labels)
        quadrants.values.map do |quadrant|
          number = quadrant[:number]
          Rect.new(number: number, label: labels[number], **quadrant[:bounds])
        end
      end

      # The six border lines mmdc draws: four outer edges, then the two
      # dividers.
      def border_lines(space)
        outer_borders(space) + dividers(space)
      end

      def outer_borders(space)
        across = space.across(HALF_BORDER)
        down = space.down(-HALF_BORDER)
        [horizontal_line(space.top, *across, EXTERNAL_BORDER),
         vertical_line(space.right, *down, EXTERNAL_BORDER),
         horizontal_line(space.bottom, *across, EXTERNAL_BORDER),
         vertical_line(space.left, *down, EXTERNAL_BORDER)]
      end

      def dividers(space)
        across = space.across(-HALF_BORDER)
        down = space.down(-HALF_BORDER)
        [vertical_line(space.mid_x, *down, INTERNAL_BORDER),
         horizontal_line(space.mid_y, *across, INTERNAL_BORDER)]
      end

      def horizontal_line(y_pos, x_start, x_end, width)
        Line.new(x1: x_start, y1: y_pos, x2: x_end, y2: y_pos,
                 stroke_width: width)
      end

      def vertical_line(x_pos, y_start, y_end, width)
        Line.new(x1: x_pos, y1: y_start, x2: x_pos, y2: y_end,
                 stroke_width: width)
      end

      # Only axis labels that were written are drawn, as in mmdc.
      def axis_labels(axes, space)
        x_labels(axes, space) + y_labels(axes, space)
      end

      def x_labels(axes, space)
        middle = !axes[:x_right].empty?
        centre = space.left + (middle ? space.half_width / 2 : 0)
        y_pos = x_label_y(space)
        written_labels([[axes[:x_left], centre],
                        [axes[:x_right], centre + space.half_width]],
                       middle, 0) { |x_pos| [x_pos, y_pos] }
      end

      # Each pair is [text, position along the axis]; the block turns that
      # position into the label's [x, y].
      def written_labels(pairs, middle, rotation)
        pairs.reject { |text, _| text.empty? }.map do |text, along|
          axis_label(text, yield(along), middle, rotation)
        end
      end

      # The x axis sits below the plot when there are points, above otherwise.
      def x_label_y(space)
        return AXIS_LABEL_PADDING + space.title unless space.x_axis_below

        AXIS_LABEL_PADDING + space.top + space.height + PADDING
      end

      def y_labels(axes, space)
        middle = !axes[:y_top].empty?
        lift = middle ? space.half_height / 2 : 0
        written_labels([[axes[:y_bottom], space.bottom - lift],
                        [axes[:y_top], space.mid_y - lift]],
                       middle, -90) { |y_pos| [AXIS_LABEL_PADDING, y_pos] }
      end

      def axis_label(text, position, middle, rotation)
        label(text, position, large_font_size, "axis",
              anchor: middle ? "middle" : "start", baseline: "hanging",
              rotation: rotation)
      end

      def quadrant_labels_by_number(quadrants, points)
        labelled = quadrants.values.select { |quadrant| quadrant[:label] }
        labelled.to_h do |quadrant|
          label = points.empty? ? centred_label(quadrant) : top_label(quadrant)
          [quadrant[:number], label]
        end
      end

      def top_label(quadrant)
        top = quadrant[:bounds][:y] + QUADRANT_TEXT_TOP_PADDING
        quadrant_label(quadrant, top, "hanging")
      end

      def centred_label(quadrant)
        bounds = quadrant[:bounds]
        middle = bounds[:y] + (bounds[:height] / 2.0)
        quadrant_label(quadrant, middle, "middle")
      end

      def quadrant_label(quadrant, y_pos, baseline)
        bounds = quadrant[:bounds]
        label(quadrant[:label], [bounds[:x] + (bounds[:width] / 2.0), y_pos],
              large_font_size, "quadrant",
              anchor: "middle", baseline: baseline)
      end

      def typed_points(points)
        points.map { |point| typed_point(point) }
      end

      def typed_point(point)
        Point.new(
          id: point[:id], x: point[:svg_x], y: point[:svg_y],
          radius: point[:radius], quadrant: point[:quadrant],
          color: point[:color], stroke_color: point[:stroke_color],
          stroke_width: point[:stroke_width], label: point_label(point)
        )
      end

      def point_label(point)
        label(
          point[:label], [point[:svg_x], point[:svg_y] + POINT_TEXT_PADDING],
          small_font_size, "point", anchor: "middle", baseline: "hanging"
        )
      end

      def title_font_size
        theme.typography&.font_size_title || 20
      end

      def large_font_size
        theme.typography&.font_size_large || 16
      end

      def small_font_size
        theme.typography&.font_size_small || 12
      end

      def label(text, position, size, style, **options)
        Label.new(
          text: text, x: position[0], y: position[1],
          font_size: size, style: style,
          text_anchor: options[:anchor], font_weight: options[:weight],
          rotation: options.fetch(:rotation, 0), baseline: options[:baseline]
        )
      end

      def transform_points(data, space)
        point_items(data).map { |point| transform_point(point, space) }
      end

      def transform_point(point, space)
        values = point_values(point)
        { id: point.id, label: point.label, quadrant: point_quadrant(point) }
          .merge(point_coordinates(values, space))
          .merge(point_style(values))
      end

      def point_values(point)
        %w[x_value y_value marker_size fill_color stroke_color stroke_width]
          .to_h { |dimension| [dimension, placement_value(point, dimension)] }
      end

      def point_coordinates(values, space)
        {
          svg_x: space.left + (values["x_value"] * space.width),
          svg_y: space.top + ((1.0 - values["y_value"]) * space.height),
        }
      end

      def point_style(values)
        {
          radius: values["marker_size"].to_f, color: values["fill_color"],
          stroke_color: values["stroke_color"],
          stroke_width: values["stroke_width"].to_f
        }
      end

      def point_quadrant(point)
        quadrant_number(placement_value(point, "x_value"),
                        placement_value(point, "y_value"))
      end

      def point_items(data)
        data.items.select { |item| item.role == "point" }
          .sort_by { |item| placement(item, "x_value").ordinal }
      end

      def placement_value(item, dimension)
        placement(item, dimension)&.value&.value
      end

      def placement(item, dimension)
        item.placements.find { |candidate| candidate.dimension == dimension }
      end

      def quadrant_number(x_value, y_value)
        return x_value >= 0.5 ? 1 : 2 if y_value >= 0.5

        x_value < 0.5 ? 3 : 4
      end
    end
  end
end
