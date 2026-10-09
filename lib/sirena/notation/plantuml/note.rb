# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # A note attached to a class: `side` is :left, :right, :top or
      # :bottom; `member` is the name after `::` or nil; `color` is the
      # `#name` or `#hex` written after the target, `stereotype` the
      # `<<name>>`; `lines` is the note text, one entry per source line.
      class Note
        attr_reader :side, :target, :member, :color, :stereotype, :lines

        # @param head [Hash] `:side`, `:target`, `:member`, `:color` and
        #   `:stereotype`, all required
        def initialize(head, lines:)
          @side = head.fetch(:side)
          @target = head.fetch(:target)
          @member = head.fetch(:member)
          @color = head.fetch(:color)
          @stereotype = head.fetch(:stereotype)
          @lines = lines
          freeze
        end
      end
    end
  end
end
