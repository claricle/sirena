# frozen_string_literal: true

require_relative 'escaping'
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

      # @param names [Array<Symbol>] attribute readers, in output order
      # @return [void]
      def self.writes_attributes(*names)
        define_method(:element_attributes) do
          names.map { |name| [name.to_s.tr('_', '-'), public_send(name)] }
        end
      end

      protected

      # Build attribute string for XML output
      #
      # @return [String] formatted attribute string
      def build_attributes
        Escaping.attributes(
          [
            ['id', id],
            ['class', class_name],
            ['transform', transform],
            ['fill', fill],
            ['fill-opacity', fill_opacity],
            ['stroke', stroke],
            ['stroke-width', stroke_width],
            ['stroke-opacity', stroke_opacity],
            ['opacity', opacity]
          ] + element_attributes
        )
      end

      # Declares the attributes an element writes, in output order.
      #
      # Six subclasses were each carrying the same shape of method — a list of
      # names paired with the matching reader. Declaring them removes that
      # repetition and, more usefully, removes the chance of one class's
      # version drifting into a different shape.
      #
      # Ruby names map to SVG names by turning underscores into hyphens, which
      # covers every attribute these elements emit (`stroke_dasharray` becomes
      # `stroke-dasharray`). A notation needing anything else should override
      # #element_attributes rather than bend this.
      #

      # Hook for subclasses to add their specific attributes.
      #
      # Returns name/value PAIRS, not rendered markup. That is deliberate: it
      # leaves Escaping.attributes as the only code that turns an attribute
      # into text, so a subclass cannot emit an unescaped one. Pairs with a
      # nil value are dropped, so callers need no conditionals.
      #
      # @return [Array<Array>] name/value pairs
      def element_attributes
        []
      end
    end
  end
end
