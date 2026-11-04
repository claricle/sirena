# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Style
        # A renderer class tied to one diagram's {Sheet}. The engine builds
        # a renderer with `new(theme:)` only, so the sheet travels in this
        # wrapper, which stands where the renderer class stood.
        class Bound
          # @return [Class, Bound] the renderer itself when the source set
          #   nothing and the renderer's own defaults already apply
          def self.wrap(renderer, sheet)
            sheet.styled? ? new(renderer, sheet) : renderer
          end

          # @param renderer [Class] a renderer taking `style:` as well as
          #   `theme:`
          # @param sheet [Sheet] the diagram's style
          def initialize(renderer, sheet)
            @renderer = renderer
            @sheet = sheet
            freeze
          end

          # @return [Object] a renderer that draws with the sheet
          def new(theme: nil)
            @renderer.new(theme: theme, style: @sheet)
          end
        end
      end
    end
  end
end
