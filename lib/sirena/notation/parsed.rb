# frozen_string_literal: true

module Sirena
  module Notation
    # What a notation's `parse` hands to the engine: the detected type, the
    # parsed diagram model, and the classes that lay it out and draw it.
    class Parsed
      attr_reader :type, :diagram, :transform, :renderer, :layout_engine, :name

      def initialize(type:, diagram:, transform:, renderer:,
                     layout_engine: nil)
        @type = type
        @diagram = diagram
        @transform = transform
        @renderer = renderer
        @layout_engine = layout_engine
        freeze
      end

      # @param name [String, nil] what the source's opener named the
      #   diagram (PlantUML's `@startuml foo`); untrusted text that never
      #   changes the drawing
      # @return [Parsed] a copy of this result carrying `name`
      def with_name(name)
        copy = clone(freeze: false)
        copy.instance_variable_set(:@name, name)
        copy.freeze
      end
    end
  end
end
