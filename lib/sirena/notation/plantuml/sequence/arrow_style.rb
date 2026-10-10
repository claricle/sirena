# frozen_string_literal: true

require_relative "arrow_end"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # How a message is drawn: the two ends, a dashed or solid shaft, and
        # which side a message to its own sender loops out on.
        class ArrowStyle
          attr_reader :head, :tail, :dashed, :leftward, :hidden, :colour

          # @param head [ArrowEnd] the end at the receiver
          # @param tail [ArrowEnd] the end at the sender
          # @param leftward [Boolean] written `<-`; only a message to its own
          #   sender draws differently for it
          # @param hidden [Boolean] written `-[hidden]>`: laid out, not drawn
          # @param colour [String, nil] written `-[#22A722]>`
          def initialize(head:, tail: ArrowEnd.new, dashed: false,
                         leftward: false, hidden: false, colour: nil)
            @head = head
            @tail = tail
            @dashed = dashed
            @leftward = leftward
            @hidden = hidden
            @colour = colour
            freeze
          end

          def self.plain(glyph, dashed: false)
            new(head: ArrowEnd.new(glyph: glyph), dashed: dashed)
          end
        end
      end
    end
  end
end
