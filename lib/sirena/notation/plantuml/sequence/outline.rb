# frozen_string_literal: true

require_relative "divider"
require_relative "fragment"
require_relative "message"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Collects the items of a diagram in source order and answers the
        # structural questions that need history: which call a `return`
        # answers, which block an `else` or `end` belongs to. Each query
        # returns false instead of adding an item it cannot place.
        class Outline
          attr_reader :items

          def initialize
            @items = []
            @calls = []
            @blocks = []
          end

          def message(message)
            @calls << message unless message.dashed
            @items << message
          end

          def reply(label)
            call = @calls.pop or return false

            message(Message.new(from: call.to, to: call.from, label: label,
                                head: :filled, dashed: true))
          end

          def note(note)
            @items << note
          end

          def after_message?
            @items.last.is_a?(Message)
          end

          def divider(label)
            @items << Divider.new(label: label)
          end

          def open_block(keyword, label)
            @blocks << keyword
            @items << Fragment.new(phase: :open, keyword: keyword,
                                   label: label)
          end

          def branch(label)
            return false if @blocks.empty?

            @items << Fragment.new(phase: :else, keyword: @blocks.last,
                                   label: label)
          end

          def close_block
            keyword = @blocks.pop or return false

            @items << Fragment.new(phase: :close, keyword: keyword)
          end

          def open_block?
            !@blocks.empty?
          end
        end
      end
    end
  end
end
