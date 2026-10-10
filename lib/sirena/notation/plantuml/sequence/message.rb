# frozen_string_literal: true

require_relative "arrow_style"
require_relative "edge"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # One arrow, normalised so `from` is always the sender: `B <- A` and
        # `A -> B` read the same. `style` is an {ArrowStyle}. `label` is the
        # source text. `from` or `to` is an {Edge} when the message has no
        # participant at that end. `number` is the `autonumber` count, or nil.
        class Message
          attr_reader :from, :to, :label, :style, :number

          def initialize(from:, to:, label:, style:, number: nil)
            @from = from
            @to = to
            @label = label
            @style = style
            @number = number
            freeze
          end

          # @return [Message] the same message, drawn with `number`
          def numbered(number)
            self.class.new(from: from, to: to, label: label, style: style,
                           number: number)
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

          # @return [Edge, nil] the end with no participant
          def edge
            [from, to].grep(Edge).first
          end

          # @return [Array<String>] the participants the message touches
          def participants
            [from, to].grep_v(Edge)
          end

          # What is drawn at the {#edge} end.
          def edge_end
            from.is_a?(Edge) ? style.tail : style.head
          end
        end
      end
    end
  end
end
