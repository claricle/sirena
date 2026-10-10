# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # A `newpage` line. PlantUML's single-image output holds only the
        # first page, so nothing after the first one is drawn.
        class PageBreak
          def initialize
            freeze
          end
        end
      end
    end
  end
end
