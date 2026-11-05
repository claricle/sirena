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
        # participant at that end. `number` is the `autonumber` {Number}, or
        # nil.
        class Message
          Label = Struct.new(:content, :font_family, keyword_init: true)

          # The text `autonumber` draws before a label, and whether it is bold.
          Number = Struct.new(:text, :bold, keyword_init: true) do
            def to_s
              text
            end
          end

          attr_reader :from, :to, :label, :style, :number, :label_family

          def initialize(from:, to:, label:, style:, number: nil)
            @from = from
            @to = to
            @label = label.is_a?(Label) ? label.content : label
            @label_family = label.is_a?(Label) ? label.font_family : nil
            @style = style
            @number = number_of(number)
            freeze
          end

          # @return [Message] the same message, drawn with `number`
          def numbered(text, bold: true)
            display = Label.new(content: label, font_family: label_family)
            self.class.new(from: from, to: to, label: display, style: style,
                           number: text && Number.new(text: text, bold: bold))
          end

          # @return [String, nil] the weight of the number
          def number_weight
            "bold" if number&.bold
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

          private

          def number_of(number)
            return number if number.nil? || number.is_a?(Number)

            Number.new(text: number.to_s, bold: true)
          end
        end
      end
    end
  end
end
