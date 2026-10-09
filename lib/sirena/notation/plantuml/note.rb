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

        def initialize(side:, target:, member:, color:, stereotype:, lines:)
          @side = side
          @target = target
          @member = member
          @color = color
          @stereotype = stereotype
          @lines = lines
          freeze
        end
      end
    end
  end
end
