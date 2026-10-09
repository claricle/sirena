# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # The extractor's result for one SVG. `root_box` is the root viewBox (else
    # numeric width/height at the origin, else nil); `max_width` is the
    # style fallback contract section 2 names for references with neither.
    class Figure
      attr_reader :elements, :root_box, :max_width

      def initialize(elements:, root_box:, max_width: nil)
        @elements = elements
        @root_box = root_box
        @max_width = max_width
      end

      def find(kind, key)
        elements.select { |e| e.kind == kind && e.key == key }
      end

      def keys
        elements.map { |e| [e.kind, e.parent, e.key] }
      end
    end
  end
end
