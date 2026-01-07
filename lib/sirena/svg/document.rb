# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'

module Sirena
  module Svg
    # SVG Document root element
    #
    # Represents the top-level <svg> element with namespace declarations,
    # viewBox, and dimension attributes. Contains all other SVG elements
    # as children.
    class Document < Lutaml::Model::Serializable
      SVG_NAMESPACE = 'http://www.w3.org/2000/svg'
      XMLNS_NAMESPACE = 'http://www.w3.org/2000/xmlns/'
      SVG_VERSION = '1.2'

      attribute :width, :float
      attribute :height, :float
      attribute :view_box, :string
      attribute :version, :string
      attribute :xmlns, :string
      attribute :children, Element, collection: true

      xml do
        root 'svg', mixed: true
        namespace SVG_NAMESPACE, 'svg'

        map_attribute 'width', to: :width
        map_attribute 'height', to: :height
        map_attribute 'viewBox', to: :view_box
        map_attribute 'version', to: :version
        map_attribute 'xmlns', to: :xmlns

        map_element 'g', to: :children
        map_element 'rect', to: :children
        map_element 'circle', to: :children
        map_element 'ellipse', to: :children
        map_element 'line', to: :children
        map_element 'path', to: :children
        map_element 'polygon', to: :children
        map_element 'polyline', to: :children
        map_element 'text', to: :children
      end

      # Initialize document with calculated viewBox if not provided
      #
      # @param width [Numeric] Document width
      # @param height [Numeric] Document height
      # @param view_box [String] ViewBox specification
      def initialize(width: nil, height: nil, view_box: nil, **args)
        super(**args)
        self.width = width
        self.height = height
        self.view_box = view_box || calculate_view_box(width, height)
        self.version = SVG_VERSION
        self.xmlns = SVG_NAMESPACE
        self.children = []
      end

      # Add an element to the document
      #
      # @param element [Element] SVG element to add
      # @return [void]
      def add_element(element)
        children << element
      end

      alias << add_element

      # Generate SVG XML string
      #
      # @return [String] XML representation of the SVG document
      def to_xml
        parts = ["<svg"]
        parts << %( width="#{width}") if width
        parts << %( height="#{height}") if height
        parts << %( viewBox="#{view_box}") if view_box
        parts << %( version="#{version}") if version
        parts << %( xmlns="#{xmlns}") if xmlns
        parts << ">"

        children.each do |child|
          parts << child.to_xml if child.respond_to?(:to_xml)
        end

        parts << "</svg>"
        parts.join("\n")
      end

      # String representation returns XML
      alias to_s to_xml

      private

      def calculate_view_box(width, height)
        return nil unless width && height

        "0 0 #{width} #{height}"
      end
    end
  end
end
