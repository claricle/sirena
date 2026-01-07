# frozen_string_literal: true

module Sirena
  module Renderer
    # Abstract base class for diagram renderers.
    #
    # Renderers convert laid-out graph structures (with computed positions)
    # into SVG documents using the Svg builder classes. Each diagram type has
    # its own renderer that maps graph elements to appropriate SVG shapes.
    #
    # The renderer implements the template method pattern, defining the
    # overall rendering pipeline while allowing subclasses to customize
    # specific rendering steps.
    #
    # @example Define a custom renderer
    #   class FlowchartRenderer < Renderer::Base
    #     def render(graph)
    #       svg = create_document(graph)
    #       render_nodes(graph, svg)
    #       render_edges(graph, svg)
    #       svg
    #     end
    #
    #     protected
    #
    #     def render_nodes(graph, svg)
    #       # Render graph nodes as SVG shapes
    #     end
    #
    #     def render_edges(graph, svg)
    #       # Render graph edges as SVG paths
    #     end
    #   end
    #
    # @abstract Subclass and implement rendering methods
    class Base
      attr_accessor :theme

      # Creates a new renderer instance.
      #
      # @param theme [Theme, nil] theme to use for rendering
      def initialize(theme: nil)
        @theme = theme || Theme::Registry.get(:default)
      end

      # Renders a laid-out graph to an SVG document.
      #
      # This method should be overridden by subclasses to implement
      # diagram-specific rendering logic.
      #
      # @param graph [Object] the laid-out elkrb graph with positions
      # @return [Svg::Document] the rendered SVG document
      # @raise [NotImplementedError] if not implemented by subclass
      def render(graph)
        raise NotImplementedError,
              "#{self.class} must implement #render(graph)"
      end

      protected

      # Creates an SVG document with appropriate dimensions.
      #
      # @param graph [Object] the graph to get dimensions from
      # @param padding [Numeric] padding around the diagram
      # @return [Svg::Document] new SVG document
      def create_document(graph, padding: 20)
        width = calculate_width(graph) + (padding * 2)
        height = calculate_height(graph) + (padding * 2)

        Svg::Document.new.tap do |doc|
          doc.width = width
          doc.height = height
          doc.view_box = "0 0 #{width} #{height}"
        end
      end

      # Calculates the total width needed for the diagram.
      #
      # Subclasses should override this to compute width from graph.
      #
      # @param graph [Object] the graph
      # @return [Numeric] the width in pixels
      def calculate_width(_graph)
        800 # Default width
      end

      # Calculates the total height needed for the diagram.
      #
      # Subclasses should override this to compute height from graph.
      #
      # @param graph [Object] the graph
      # @return [Numeric] the height in pixels
      def calculate_height(_graph)
        600 # Default height
      end

      # Helper methods for accessing theme properties

      # Gets a color property from the theme.
      #
      # @param property [Symbol] property name
      # @return [String, nil] color value
      def theme_color(property)
        theme&.colors&.send(property)
      rescue NoMethodError
        nil
      end

      # Gets a typography property from the theme.
      #
      # @param property [Symbol] property name
      # @return [String, Float, nil] typography value
      def theme_typography(property)
        theme&.typography&.send(property)
      rescue NoMethodError
        nil
      end

      # Gets a shape property from the theme.
      #
      # @param property [Symbol] property name
      # @return [Float, String, nil] shape value
      def theme_shape(property)
        theme&.shapes&.send(property)
      rescue NoMethodError
        nil
      end

      # Gets a spacing property from the theme.
      #
      # @param property [Symbol] property name
      # @return [Float, nil] spacing value
      def theme_spacing(property)
        theme&.spacing&.send(property)
      rescue NoMethodError
        nil
      end

      # Gets an effect property from the theme.
      #
      # @param property [Symbol] property name
      # @return [Boolean, Float, String, nil] effect value
      def theme_effect(property)
        theme&.effects&.send(property)
      rescue NoMethodError
        nil
      end

      # Applies theme styles to a node element.
      #
      # @param element [Svg::Element] SVG element
      # @return [void]
      def apply_theme_to_node(element)
        element.fill = theme_color(:node_fill) if theme_color(:node_fill)
        element.stroke = theme_color(:node_stroke) if theme_color(:node_stroke)
        if theme_shape(:stroke_width)
          element.stroke_width = theme_shape(:stroke_width).to_s
        end
      end

      # Applies theme styles to an edge element.
      #
      # @param element [Svg::Element] SVG element
      # @return [void]
      def apply_theme_to_edge(element)
        element.stroke = theme_color(:edge_stroke) if theme_color(:edge_stroke)
        if theme_shape(:stroke_width)
          element.stroke_width = theme_shape(:stroke_width).to_s
        end
      end

      # Applies theme styles to a text element.
      #
      # @param element [Svg::Text] SVG text element
      # @return [void]
      def apply_theme_to_text(element)
        element.fill = theme_color(:label_text) if theme_color(:label_text)
        if theme_typography(:font_family)
          element.font_family = theme_typography(:font_family)
        end
        if theme_typography(:font_size_normal)
          element.font_size = theme_typography(:font_size_normal).to_s
        end
      end

      # Creates default style for SVG elements.
      #
      # @param element_type [Symbol] type of element (:node, :edge, :text)
      # @return [Svg::Style] style object
      def default_style(element_type)
        case element_type
        when :node
          Svg::Style.new.tap do |style|
            style.fill = theme_color(:node_fill) || '#ffffff'
            style.stroke = theme_color(:node_stroke) || '#000000'
            style.stroke_width =
              (theme_shape(:stroke_width) || 2).to_s
          end
        when :edge
          Svg::Style.new.tap do |style|
            style.fill = 'none'
            style.stroke = theme_color(:edge_stroke) || '#000000'
            style.stroke_width =
              (theme_shape(:stroke_width) || 2).to_s
          end
        when :text
          Svg::Style.new.tap do |style|
            style.fill = theme_color(:label_text) || '#000000'
            style.font_family =
              theme_typography(:font_family) || 'Arial, sans-serif'
            style.font_size =
              (theme_typography(:font_size_normal) || 14).to_s
            style.text_anchor = 'middle'
          end
        else
          Svg::Style.new
        end
      end

      # Creates an SVG path data string from bend points.
      #
      # @param start_point [Hash] hash with :x and :y keys
      # @param end_point [Hash] hash with :x and :y keys
      # @param bend_points [Array<Hash>] array of hashes with :x and :y
      # @return [String] SVG path data string
      def create_path_data(start_point, end_point, bend_points = [])
        points = [start_point] + bend_points + [end_point]
        path_parts = ["M #{points[0][:x]} #{points[0][:y]}"]

        points[1..].each do |point|
          path_parts << "L #{point[:x]} #{point[:y]}"
        end

        path_parts.join(' ')
      end

      # Adds an arrow marker to the SVG document.
      #
      # @param svg [Svg::Document] the SVG document
      # @param id [String] unique identifier for the marker
      # @return [void]
      def add_arrow_marker(svg, id: 'arrow')
        # This is a placeholder for actual marker implementation
        # Subclasses can implement this to add arrow markers
      end
    end

    # Error raised during rendering.
    class RenderError < StandardError; end
  end
end
