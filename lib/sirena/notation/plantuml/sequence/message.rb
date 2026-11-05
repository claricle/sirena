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
        # participant at that end. `number` is the `autonumber` text, or nil, and
        # `number_weight` the weight it is drawn in.
        class Message
          Label = Struct.new(:content, :font_family, keyword_init: true)

          attr_reader :from, :to, :label, :style, :number, :number_weight,
                      :label_family

          def initialize(from:, to:, label:, style:, number: nil,
                         number_weight: nil)
            @from = from
            @to = to
            @label = label.is_a?(Label) ? label.content : label
            @label_family = label.is_a?(Label) ? label.font_family : nil
            @style = style
            @number = number
            @number_weight = number ? number_weight : nil
            freeze
          end

          # @return [Message] the same message, drawn with `number`
          def numbered(number, weight = "bold")
            display = Label.new(content: label, font_family: label_family)
            self.class.new(from: from, to: to, label: display, style: style,
                           number: number, number_weight: weight)
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
