# frozen_string_literal: true

require_relative "base"
require_relative "pie_legend"
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
      # mmdc: a 450px square, 40px margin, radius 185, labels at 0.75r.
      RADIUS = 185
      CENTER_X = 225
      CENTER_Y = 225
      LABEL_OFFSET = RADIUS * 0.75
      TITLE_Y = CENTER_Y - 200
      HEIGHT = 450
      # mmdc draws slice labels, legend rows and the title at fixed sizes,
      # whatever the theme says.
      TEXT_SIZE = 17
      TITLE_SIZE = 25
      # mmdc drops a slice under this share of the total, label and all.
      MIN_PERCENT = 1.0

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
        attribute :legend, PieLegendEntry, collection: true,
                                           default: -> { [] }
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
        legend = legend_entries(graph)
        width = [HEIGHT, pie_legend.width(legend)].max
        Scene.new(
          id: graph[:id] || "pie", width: width, height: HEIGHT,
          view_box: "0 0 #{width} #{HEIGHT}",
          title: title_label(graph[:title]), slices: typed_slices(graph),
          legend: legend, **accessibility(graph)
        )
      end

      def accessibility(graph)
        { acc_title: graph[:acc_title],
          acc_description: graph[:acc_description] }
      end

      def legend_entries(graph)
        pie_legend.entries(ranked(graph), graph[:show_data])
      end

      def pie_legend
        PieLegend.new(center_y: CENTER_Y,
                      font_size: TEXT_SIZE)
      end

      def title_label(title)
        return unless title

        Label.new(
          text: title, x: CENTER_X, y: TITLE_Y,
          font_size: TITLE_SIZE,
          text_anchor: "middle", font_weight: "bold"
        )
      end

      # mmdc lays slices out largest first (stable); the legend keeps
      # input order. A slice under MIN_PERCENT of the total is not drawn
      # (sweep 0), and the slices that are drawn share the whole circle.
      def ranked(graph)
        slices = graph[:slices] || []
        order = slices.each_index.sort_by { |i| [-slices[i][:value].to_f, i] }
        scale = sweep_scale(slices)
        slices.each_with_index.map do |slice, index|
          slice.merge(input_index: index, rank: order.index(index),
                      sweep: scale * (shown?(slice) ? weight(slice) : 0.0))
        end
      end

      def shown?(slice)
        slice[:percentage] >= MIN_PERCENT
      end

      def sweep_scale(slices)
        shown_total = slices.select { |slice| shown?(slice) }
                            .sum { |slice| weight(slice) }
        shown_total.zero? ? 0.0 : 360.0 / shown_total
      end

      # A hand-built graph may carry only the angle.
      def weight(slice)
        slice[:value] || slice[:angle]
      end

      # Angles accumulate in rank order; slices are emitted in input order
      # so document order matches the legend order.
      def typed_slices(graph)
        start_angle = -90.0
        typed = ranked(graph).sort_by { |slice| slice[:rank] }.map do |slice|
          finish_angle = start_angle + slice[:sweep]
          result = typed_slice(slice, start_angle, finish_angle)
          start_angle = finish_angle
          [slice[:input_index], result]
        end
        typed.sort_by(&:first).filter_map(&:last)
      end

      def typed_slice(slice, start_angle, finish_angle)
        return if slice[:sweep].zero?

        Slice.new(
          id: slice[:id] || "slice_#{slice[:input_index]}",
          path: slice_path(start_angle, finish_angle),
          color_index: slice[:rank],
          percentage: slice[:percentage], angle: slice[:sweep],
          label: slice_label(slice, (start_angle + finish_angle) / 2.0)
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

      def slice_label(slice, angle)
        x_position, y_position = circle_point(angle, LABEL_OFFSET)
        Label.new(
          text: "#{slice[:percentage].round}%", x: x_position, y: y_position,
          font_size: TEXT_SIZE,
          text_anchor: "middle", dominant_baseline: "middle"
        )
      end

      def circle_point(angle, radius)
        radians = angle * Math::PI / 180.0
        [CENTER_X + (radius * Math.cos(radians)),
         CENTER_Y + (radius * Math.sin(radians))]
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
