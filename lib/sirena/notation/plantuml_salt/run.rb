# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLSalt
      # A stretch of text drawn in one style. `style` may hold `:bold`,
      # `:italic`, `:underline`, `:strike` (true), `:color` (a String) and
      # `:size` (a Numeric, in points).
      class Run
        attr_reader :text

        def initialize(text, **style)
          @text = text
          @style = style.freeze
          freeze
        end

        %i[bold italic underline strike].each do |name|
          define_method(name) { @style.fetch(name, false) }
        end

        # @return [Numeric, nil] the font size, when it is not the default
        def size
          @style[:size]
        end

        # @return [String, nil] a colour name or hex digits
        def color
          @style[:color]
        end
      end
    end
  end
end
