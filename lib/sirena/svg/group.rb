# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'

module Sirena
  module Svg
    # SVG Group element <g>
    #
    # Groups multiple SVG elements together for collective transformation
    # and styling. Implements the Composite pattern for hierarchical
    # SVG structure.
    class Group < Element
      attribute :children, Element, collection: true

      xml do
        root 'g'
        map_attribute 'id', to: :id
        map_attribute 'class', to: :class_name
        map_attribute 'transform', to: :transform
        map_attribute 'fill', to: :fill
        map_attribute 'stroke', to: :stroke
        map_attribute 'stroke-width', to: :stroke_width
        map_attribute 'opacity', to: :opacity

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

      def initialize(**args)
        super(**args)
        self.children ||= []
      end

      # Add a child element to this group
      #
      # @param element [Element] SVG element to add
      # @return [void]
      def add_child(element)
        children << element
      end

      alias << add_child

      # Generate XML with children
      #
      # @return [String] XML string
      def to_xml
        attrs = build_attributes

        if children.empty?
          "<g#{attrs}/>"
        else
          parts = ["<g#{attrs}>"]
          children.each do |child|
            parts << "  #{child.to_xml}" if child.respond_to?(:to_xml)
          end
          parts << "</g>"
          parts.join("\n")
        end
      end
    end
  end
end
