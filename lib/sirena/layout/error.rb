# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/error"
require_relative "../notation/mermaid/ir_adapters/error"

module Sirena
  module Layout
    # Error diagram transformer for converting error models to renderable
    # structure.
    #
    # Error diagrams have no complex layout requirements - they simply display
    # an error message. This transformer prepares basic data for rendering.
    #
    # @example Transform an error diagram
    #   layout = Error.new
    #   scene = layout.call(error_diagram)
    class Error < Base
      class Box < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :corner_radius, :float
      end

      class Circle < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :radius, :float
      end

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
        attribute :box, Box
        attribute :icon, Circle
        attribute :mark, Box
        attribute :dot, Circle
        attribute :label, Label
      end

      def self.from_graph(graph, theme: nil)
        layout = new
        layout.theme = theme if theme
        layout.send(:scene_from_graph, graph)
      end

      # Converts an error diagram to a simple data structure.
      #
      # Error diagrams don't need layout computation. This method validates
      # the diagram and returns a structure for the renderer.
      #
      # @param diagram [Diagram::Error] the error diagram to transform
      # @return [Hash] data structure for rendering
      def build_graph(diagram)
        data = ir_data(diagram)
        {
          id: data.id, title: data.label,
          message: data.items.find { |item| item.role == "message" }&.label,
          metadata: {
            diagram_type: :error,
          }
        }
      end

      private

      def scene(diagram)
        scene_from_graph(build_graph(diagram))
      end

      def ir_data(diagram)
        return diagram if diagram.is_a?(IR::Data)

        Notation::Mermaid::IRAdapters::Error.call(diagram)
      end

      def scene_from_graph(graph)
        Scene.new(
          id: graph[:id] || "error", title: graph[:title],
          width: 2412, height: 512, view_box: "0 0 2412 512",
          box: error_box,
          icon: Circle.new(x: 256, y: 256, radius: 256),
          mark: error_mark,
          dot: Circle.new(x: 256, y: 384, radius: 16),
          label: error_label(graph)
        )
      end

      def error_box
        Box.new(x: 0, y: 0, width: 2412, height: 512, corner_radius: 8)
      end

      def error_mark
        Box.new(x: 240, y: 128, width: 32, height: 192, corner_radius: 16)
      end

      def error_label(graph)
        Label.new(
          text: graph[:message] || "Error", x: 1440, y: 250,
          font_size: font_size, text_anchor: "middle", font_weight: "bold"
        )
      end

      def font_size
        value = theme.typography&.font_size_base
        value&.positive? ? value : 16
      rescue NoMethodError
        16
      end
    end
  end
end
