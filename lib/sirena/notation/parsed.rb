# frozen_string_literal: true

module Sirena
  module Notation
    # What a notation's `parse` hands to the engine: the detected type, the
    # parsed diagram model, and the classes that lay it out and draw it.
    class Parsed
      attr_reader :type, :diagram, :transform, :renderer

      def initialize(type:, diagram:, transform:, renderer:)
        @type = type
        @diagram = diagram
        @transform = transform
        @renderer = renderer
        freeze
      end
    end
  end
end
