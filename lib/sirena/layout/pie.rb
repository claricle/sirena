# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/pie"
require_relative "../notation/mermaid/ir_adapters/pie"

module Sirena
  module Layout
    # Pie chart transformer for converting pie models to renderable structure.
    #
    # Unlike flowcharts and sequence diagrams which require complex layout
    # computation, pie charts have a fixed circular layout. This transformer
    # simply validates and prepares the diagram data for direct rendering.
    #
    # @example Transform a pie chart
    #   transform = Pie.new
    #   data = transform.to_graph(pie_diagram)
    class Pie < Base
      RADIUS = 150
      CENTER_X = 250
      CENTER_Y = 200
      LABEL_OFFSET = 180
      TITLE_Y = 40

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :text_anchor, :string
        attribute :dominant_baseline, :string
        attribute :font_weight, :string
      end

      class Slice < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :path, :string
        attribute :color_index, :integer
        attribute :percentage, :float
        attribute :angle, :float
        attribute :label, Label
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :acc_title, :string
        attribute :acc_description, :string
        attribute :title, Label
        attribute :slices, Slice, collection: true, default: -> { [] }
      end

      def self.from_graph(graph, theme: nil)
        layout = new
        layout.theme = theme if theme
        layout.send(:scene_from_graph, graph)
      end

      # Converts a pie diagram to a simple data structure.
      #
      # Pie charts don't need graph layout computation since they have
      # a fixed circular layout. This method validates the diagram and
      # returns a simple structure for the renderer.
      #
      # @param diagram [Diagram::Pie] the pie diagram to transform
      # @return [Hash] data structure for rendering
      def build_graph(diagram)
        data = ir_data(diagram)
        slices = transform_slices(data)
        {
          id: data.id, title: data.label,
          show_data: data_value(data, "show_values", false),
          acc_title: data.accessibility_title,
          acc_description: data.accessibility_description,
          slices: slices,
          metadata: {
            total_value: slices.sum { |slice| slice[:value] },
            slice_count: slices.length,
          }
        }
      end

      private

      def scene(diagram)
        scene_from_graph(build_graph(diagram))
      end

      def ir_data(diagram)
        return diagram if diagram.is_a?(IR::Data)

        Notation::Mermaid::IRAdapters::Pie.call(diagram)
      end

      def scene_from_graph(graph)
        width = 500
        height = graph[:title] ? 460 : 400
        Scene.new(
          id: graph[:id] || "pie", width: width, height: height,
          view_box: "0 0 #{width} #{height}",
          acc_title: graph[:acc_title],
          acc_description: graph[:acc_description],
          title: title_label(graph[:title]), slices: typed_slices(graph)
        )
      end

      def title_label(title)
        return unless title

        Label.new(
          text: title, x: CENTER_X, y: TITLE_Y,
          font_size: font_size(:font_size_large, 18),
          text_anchor: "middle", font_weight: "bold"
        )
      end

      def typed_slices(graph)
        start_angle = -90.0
        (graph[:slices] || []).map.with_index do |slice, index|
          angle = slice[:angle]
          finish_angle = start_angle + angle
          typed = typed_slice(slice, index, start_angle, finish_angle,
                              graph[:show_data])
          start_angle = finish_angle
          typed
        end
      end

      def typed_slice(slice, index, start_angle, finish_angle, show_data)
        Slice.new(
          id: slice[:id] || "slice_#{index}",
          path: slice_path(start_angle, finish_angle), color_index: index,
          percentage: slice[:percentage], angle: slice[:angle],
          label: slice_label(slice, (start_angle + finish_angle) / 2.0,
                             show_data)
        )
      end

      def slice_path(start_angle, finish_angle)
        start_x, start_y = circle_point(start_angle, RADIUS)
        finish_x, finish_y = circle_point(finish_angle, RADIUS)
        large_arc = (finish_angle - start_angle) > 180 ? 1 : 0
        [
          "M #{CENTER_X} #{CENTER_Y}", "L #{start_x} #{start_y}",
          "A #{RADIUS} #{RADIUS} 0 #{large_arc} 1 #{finish_x} #{finish_y}",
          "Z"
        ].join(" ")
      end

      def slice_label(slice, angle, show_data)
        x_position, y_position = circle_point(angle, LABEL_OFFSET)
        text = slice[:label].to_s
        text += ": #{slice[:percentage].round(1)}%" if show_data
        Label.new(
          text: text, x: x_position, y: y_position,
          font_size: font_size(:font_size_small, 12),
          text_anchor: "middle", dominant_baseline: "middle"
        )
      end

      def circle_point(angle, radius)
        radians = angle * Math::PI / 180.0
        [CENTER_X + (radius * Math.cos(radians)),
         CENTER_Y + (radius * Math.sin(radians))]
      end

      def font_size(name, fallback)
        value = theme.typography&.public_send(name)
        value&.positive? ? value : fallback
      end

      def transform_slices(data)
        segments = segment_values(data)
        total = segment_total(segments)
        segments.map.with_index do |segment, index|
          value = segment.value.value
          share = proportional_share(value, total)
          {
            id: segment.id, label: segment.label, value: value,
            percentage: share * 100.0,
            angle: share * 360.0,
            index: index
          }
        end
      end

      def segment_values(data)
        data.values.select { |value| value.role == "segment" }
      end

      def segment_total(segments)
        segments.sum { |segment| segment.value.value }
      end

      def proportional_share(value, total)
        total.zero? ? 0.0 : value / total
      end

      def data_value(data, role, fallback)
        entry = data.values.find { |value| value.role == role }
        entry ? entry.value.value : fallback
      end
    end
  end
end
