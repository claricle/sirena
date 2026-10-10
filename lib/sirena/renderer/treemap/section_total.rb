# frozen_string_literal: true

module Sirena
  module Renderer
    class Treemap < Base
      # Sums the leaf values under a section so the section can show a total,
      # as mmdc does. The layout only labels leaves.
      class SectionTotal
        def initialize(cell)
          @cell = cell
        end

        # The formatted total, or nil when the section has no leaf values.
        def text
          leaves = leaf_values(@cell)
          return if leaves.empty?

          total = leaves.sum
          total == total.to_i ? total.to_i.to_s : format("%.1f", total)
        end

        private

        def leaf_values(cell)
          return cell.children.flat_map { |kid| leaf_values(kid) } if
            cell.children.any?

          cell.value_label ? [Float(cell.value_label.text)] : []
        end
      end
    end
  end
end
