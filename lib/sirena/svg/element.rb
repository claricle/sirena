# frozen_string_literal: true

require 'lutaml/model'
require_relative 'style'

module Sirena
  module Svg
    # Base class for all SVG elements.
    #
    # Provides common attributes and functionality shared by all SVG elements
    # including styling, transformation, and identification.
    class Element < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :class_name, :string
      attribute :style, Svg::Style
      attribute :transform, :string
      attribute :fill, :string
      attribute :fill_opacity, :string
      attribute :stroke, :string
      attribute :stroke_width, :string
      attribute :stroke_opacity, :string
      attribute :opacity, :float

      # Generate XML representation of this element
      #
      # @return [String] XML string
      def to_xml
        tag = self.class.name.split('::').last.downcase
        attrs = build_attributes

        "<#{tag}#{attrs}/>"
      end

      protected

      # Build attribute string for XML output
      #
      # @return [String] formatted attribute string
      def build_attributes
        attrs = []
        attrs << %( id="#{id}") if id
        attrs << %( class="#{class_name}") if class_name
        attrs << %( transform="#{transform}") if transform
        attrs << %( fill="#{fill}") if fill
        attrs << %( fill-opacity="#{fill_opacity}") if fill_opacity
        attrs << %( stroke="#{stroke}") if stroke
        attrs << %( stroke-width="#{stroke_width}") if stroke_width
        attrs << %( stroke-opacity="#{stroke_opacity}") if stroke_opacity
        attrs << %( opacity="#{opacity}") if opacity

        # Add element-specific attributes
        attrs.concat(element_attributes)

        attrs.join
      end

      # Hook for subclasses to add their specific attributes
      #
      # @return [Array<String>] array of attribute strings
      def element_attributes
        []
      end
    end
  end
end
