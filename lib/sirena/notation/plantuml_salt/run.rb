# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLSalt
      # A stretch of text drawn in one style. `style` may hold `:bold`,
      # `:italic`, `:underline`, `:strike` (true) and `:color` (a String).
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

        # @return [String, nil] a colour name or hex digits
        def color
          @style[:color]
        end
      end
    end
  end
end
