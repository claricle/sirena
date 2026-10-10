# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/info"
require_relative "../notation/mermaid/ir_adapters/info"

module Sirena
  module Layout
    # Info diagram transformer for converting info models to renderable
    # structure.
    #
    # Info diagrams have no complex layout requirements - they simply display
    # an informational message. This transformer prepares basic data for
    # rendering.
    #
    # @example Transform an info diagram
    #   layout = Info.new
    #   scene = layout.call(info_diagram)
    class Info < Base
      WIDTH = 400
      HEIGHT = 100
      VERSION_TEXT = "v11.12.0"

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :text_anchor, :string
        attribute :font_weight, :string
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :title, :string
        attribute :view_box, :string
        attribute :label, Label
      end

      def self.from_graph(graph, theme: nil)
        layout = new
        layout.theme = theme if theme
        layout.send(:scene_from_graph, graph)
      end

      # Converts an info diagram to a simple data structure.
      #
      # Info diagrams don't need layout computation. This method validates
      # the diagram and returns a structure for the renderer.
      #
      # @param diagram [Diagram::Info] the info diagram to transform
      # @return [Hash] data structure for rendering
      def build_graph(diagram)
        data = ir_data(diagram)
        {
          id: data.id, title: data.label,
          show_info: data_value(data, "show_information", false),
          metadata: {
            diagram_type: :info,
          }
        }
      end

      private

      def scene(diagram)
        scene_from_graph(build_graph(diagram))
      end

      def ir_data(diagram)
        return diagram if diagram.is_a?(IR::Data)

        Notation::Mermaid::IRAdapters::Info.call(diagram)
      end

      def data_value(data, role, fallback)
        entry = data.values.find { |value| value.role == role }
        entry ? entry.value.value : fallback
      end

      # mmdc draws only the mermaid version, centred at (100, 40) in a
      # 400x100 canvas (mermaid's infoRenderer:
      # configureSvgSize(svg, 100, 400)).
      def scene_from_graph(graph)
        Scene.new(
          id: graph[:id] || "info", title: graph[:title],
          width: WIDTH, height: HEIGHT, view_box: "0 0 #{WIDTH} #{HEIGHT}",
          label: version_label
        )
      end

      def version_label
        Label.new(
          text: VERSION_TEXT, x: 100, y: 40, font_size: 32,
          text_anchor: "middle", font_weight: nil
        )
      end
    end
  end
end
