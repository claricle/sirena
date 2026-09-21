# frozen_string_literal: true

module Sirena
  module Layout
    # Marks the Hash a not-yet-converted layout returned from
    # Base#call, so the Engine can tell it apart from a Scene.
    #
    # Temporary: TODO.architecture item 06 deletes this class with the
    # last `build_graph` layout. Only the Engine unwraps it, before Grid
    # runs; a renderer must never receive one.
    class Legacy
      # @return [Hash] the graph the layout built
      attr_reader :payload

      def initialize(payload)
        @payload = payload
      end
    end
  end
end
