# frozen_string_literal: true

require_relative "appearance"
require_relative "chrome"
require_relative "keyword_defaults"
require_relative "message"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # What the sequence parser returns: participants in order of first
        # mention, the items (messages, notes, fragment edges, dividers) in
        # source order and the boxes around neighbouring participants.
        # Private to this notation.
        class Diagram
          EXTRAS = { footbox: true, warnings: [].freeze, title: nil,
                     chrome: Chrome::NONE }.freeze
          private_constant :EXTRAS

          attr_reader :participants, :items, :boxes, :appearance, :warnings,
                      :title, :chrome

          # @param appearance [Appearance] what skinparam and `<style>` set
          # @param footbox [Boolean] false after `hide footbox`
          # @param warnings [Array<String>] drawn as banners above the heads
          # @param title [String, nil] the lines drawn above everything
          # @param chrome [Chrome] the header, footer, caption and legend
          def initialize(participants:, items:, boxes: [].freeze,
                         appearance: Appearance.new, **extras)
            extras = KeywordDefaults.resolve(extras, EXTRAS)
            @participants = participants
            @items = items
            @boxes = boxes
            @appearance = appearance
            @footbox = extras[:footbox]
            @warnings = extras[:warnings]
            @title = extras[:title]
            @chrome = extras[:chrome]
            freeze
          end

          # @return [Integer, nil] the narrowest participant head asked for
          def min_head_width
            appearance.min_width
          end

          def footbox?
            @footbox
          end

          # @return [Diagram] this diagram with other items
          def with_items(items)
            Diagram.new(participants: participants, items: items,
                        boxes: boxes, appearance: appearance,
                        footbox: footbox?, warnings: warnings, title: title,
                        chrome: chrome)
          end

          def messages
            items.grep(Message)
          end

          # The parser refuses a diagram with no participant.
          def valid?
            !participants.empty?
          end

          def diagram_type
            :sequence_diagram
          end
        end
      end
    end
  end
end
