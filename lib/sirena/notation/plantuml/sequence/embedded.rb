# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # A sequence diagram written inside a note between `{{` and `}}`
        # lines. The block is the whole note body, and its first line may be
        # `scale N`.
        class Embedded
          OPEN = /\A\{\{\z/
          CLOSE = /\A\}\}\z/
          SCALE = /\Ascale[ \t]+(\d+(?:\.\d+)?)\z/i
          private_constant :OPEN, :CLOSE, :SCALE

          # @return [Boolean] whether a note body line opens an embedded
          #   block
          def self.opens?(line)
            OPEN.match?(line.strip)
          end

          # @return [Boolean] whether a note body line closes one
          def self.closes?(line)
            CLOSE.match?(line.strip)
          end

          # @param text [String] the note body
          # @return [Embedded, nil] nil when the body is not exactly one
          #   block
          def self.read(text)
            lines = text.split("\n", -1).map(&:strip)
            return unless whole?(lines)

            body = lines[1..-2]
            scale = SCALE.match(body.first.to_s)
            body = body.drop(1) if scale
            new(body.join("\n"), scale ? scale[1].to_f : 1.0)
          end

          # The block opens on the first line and only closes on the last.
          def self.whole?(lines)
            return false unless lines.size > 1
            return false unless opens?(lines.first) && closes?(lines.last)

            early_close(lines).nil?
          end
          private_class_method :whole?

          # @return [Integer, nil] the index of a line before the last that
          #   closes the opening line's block
          def self.early_close(lines)
            depth = 0
            lines[0..-2].each_index.find do |index|
              depth += 1 if opens?(lines[index])
              depth -= 1 if closes?(lines[index])
              depth.zero?
            end
          end
          private_class_method :early_close

          attr_reader :body, :scale

          def initialize(body, scale)
            @body = body
            @scale = scale
            freeze
          end

          # @return [String] the block as a diagram of its own
          def document
            "@startuml\n#{body}\n@enduml\n"
          end
        end
      end
    end
  end
end
