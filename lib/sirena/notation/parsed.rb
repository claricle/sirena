# frozen_string_literal: true

module Sirena
  module Notation
    # What a notation's `parse` hands to the engine: the detected type, the
    # parsed diagram model, and the classes that lay it out and draw it.
    Parsed = Struct.new(:type, :diagram, :transform, :renderer,
                        keyword_init: true)
  end
end
