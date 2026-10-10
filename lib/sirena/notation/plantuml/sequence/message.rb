# frozen_string_literal: true

require_relative "arrow_style"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # One arrow, normalised so `from` is always the sender: `B <- A` and
        # `A -> B` read the same. `style` is an {ArrowStyle}. `label` is the
        # source text.
        class Message
          attr_reader :from, :to, :label, :style

          def initialize(from:, to:, label:, style:)
            @from = from
            @to = to
            @label = label
            @style = style
            freeze
          end

          def head
            style.head.glyph
          end

          def dashed
            style.dashed
          end

          # Written `<-`: a message to its own sender loops out on the left.
          def leftward?
            style.leftward
          end

          # True for a message written after `&`; see {ParallelMessage}.
          def parallel?
            false
          end

          def self_message?
            from == to
          end
        end
      end
    end
  end
end
