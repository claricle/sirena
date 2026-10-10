# frozen_string_literal: true

require_relative "activation"
require_relative "arrow_style"
require_relative "destroy"
require_relative "divider"
require_relative "fragment"
require_relative "message"
require_relative "page_break"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Collects the items of a diagram in source order and answers the
        # structural questions that need history: which call a `return`
        # answers, which block an `else` or `end` belongs to. Each query
        # returns false instead of adding an item it cannot place.
        class Outline
          def initialize
            @items = []
            @calls = []
            @blocks = []
            @depth = Hash.new(0)
            @number = nil
          end

          # @return [Array] the items of the first page, which ends with its
          #   {PageBreak}; later pages are read but not kept.
          def items
            cut = @items.index { |item| item.is_a?(PageBreak) }
            cut ? @items.first(cut + 1) : @items
          end

          # `marks` are the changes written on the same line, as
          # [phase, id, color] triples; phase is :on, :off or :destroy.
          def message(message, marks = [])
            message = numbered(message) or return false
            @calls << message unless message.dashed
            @items << message
            marks.each { |phase, id, color| mark(phase, id, color) }
          end

          # PlantUML draws nothing for a `--` or `deactivate` on a
          # participant with no open bar, so that change is dropped.
          # Messages after this line are numbered from `start`.
          def autonumber(start)
            @number = start
          end

          def activation(phase, id, color = nil)
            return true unless allowed?(phase, id)

            @depth[id] += phase == :on ? 1 : -1
            @items << Activation.new(participant: id, phase: phase,
                                     color: color)
          end

          def destroy(id)
            @items << Destroy.new(participant: id)
          end

          def active?(id)
            @depth[id].positive?
          end

          def allowed?(phase, id)
            phase != :off || @depth[id].positive?
          end

          def reply(label)
            call = @calls.pop or return false
            return false if call.edge

            style = ArrowStyle.plain(:filled, dashed: true)
            message(Message.new(from: call.to, to: call.from, label: label,
                                style: style))
          end

          def note(note)
            @items << note
          end

          def ref(ref)
            @items << ref
          end

          # Whether the last thing drawn is a message, bars opened or
          # closed after it aside: a note still hangs off that message.
          def after_message?
            last = @items.reverse_each.find { |i| !i.is_a?(Activation) }
            last.is_a?(Message)
          end

          def after_ref?
            @items.last.is_a?(Ref)
          end

          def after_block?
            last = @items.last
            last.is_a?(Fragment) && last.phase == :close
          end

          # Whether a line starting with `&` has an element to share a row
          # with: a message, a note or a block that has just closed.
          def anchored?
            last = @items.reverse_each.find do |item|
              !item.is_a?(Activation) && !item.is_a?(Destroy)
            end
            last.is_a?(Message) || last.is_a?(Note) ||
              (last.is_a?(Fragment) && last.phase == :close)
          end

          # False inside a block, which a page would have to cut in two.
          def newpage
            return false if open_block?

            @items << PageBreak.new
          end

          def divider(label)
            @items << Divider.new(label: label)
          end

          def open_block(keyword, label, parallel: false)
            @blocks << keyword
            @items << Fragment.new(phase: :open, keyword: keyword,
                                   label: label, parallel: parallel)
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

          private

          # Under `autonumber` a message takes the next number. One with no
          # label or a line break in it is not drawn; false then.
          def numbered(message)
            return message unless @number
            return if message.label.to_s.strip.empty?
            return if message.label.include?("\\n")

            message.numbered(@number).tap { @number += 1 }
          end

          def mark(phase, id, color)
            phase == :destroy ? destroy(id) : activation(phase, id, color)
          end
        end
      end
    end
  end
end
