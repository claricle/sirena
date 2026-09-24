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

      protected

      # The open tag, each child's entries indented one level, then the close
      # tag.
      #
      # Indents entries rather than lines: a Text holding a newline would
      # otherwise have its own content indented along with the markup.
      #
      # `children` is a plain Array that enforces no type, so a caller can put
      # anything in one; nothing in the gem does. A foreign object is skipped
      # rather than serialized. That narrows the old test — anything answering
      # to `to_xml` used to be written out — because indenting a child by its
      # entries needs the entries, and only an Element has them.
      #
      # @return [Array<String>] structural lines for this group
      def xml_lines
        attrs = build_attributes

        return ["<g#{attrs}/>"] if children.empty?

        child_lines = children.flat_map do |child|
          next [] unless child.is_a?(Element)

          child.xml_lines.map { |line| "  #{line}" }
        end
        ["<g#{attrs}>", *child_lines, "</g>"]
      end
    end
  end
end
