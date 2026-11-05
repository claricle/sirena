# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # One box, diamond, bar or terminal in an activity diagram.
        class Node
          # @return [String] stable id, `n<index>` in source order
          attr_reader :id
          # @return [Symbol] :start, :stop, :kill, :action, :decision, :merge or
          #   :bar
          attr_reader :kind
          # @return [String, nil] label, lines separated by newlines
          attr_reader :text
          # @return [String, nil] fill colour from `#colour:` or a lane
          attr_reader :fill
          # @return [String, nil] swimlane name
          attr_accessor :lane
          # @return [String, nil] enclosing partition name
          attr_accessor :partition
          # @return [Boolean] whether the node came from the legacy `(*)`
          #   syntax, which draws a decision as a bare diamond with its
          #   condition beside it and a bar without its name
          attr_accessor :legacy
          # @return [Array<Note>] notes attached to the node
          attr_reader :notes

          def initialize(id:, kind:, text: nil, fill: nil)
            @id = id
            @kind = kind
            @text = text
            @fill = fill
            @legacy = false
            @notes = []
          end

          # @return [Array<String>] the label's lines
          def lines
            text.to_s.split("\n")
          end
        end
      end
    end
  end
end
