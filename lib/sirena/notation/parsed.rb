# frozen_string_literal: true

module Sirena
  module Notation
    # What a notation's `parse` hands to the engine: the detected type, the
    # parsed diagram model, and the classes that lay it out and draw it.
    class Parsed
      attr_reader :type, :diagram, :transform, :renderer, :layout_engine

      def initialize(type:, diagram:, transform:, renderer:,
                     layout_engine: nil)
        @type = type
        @diagram = diagram
        @transform = transform
        @renderer = renderer
        @layout_engine = layout_engine
        freeze
      end
    end
  end
end
