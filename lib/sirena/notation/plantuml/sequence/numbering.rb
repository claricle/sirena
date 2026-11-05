# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # What an `autonumber` line sets: the first number, the step between
        # numbers and the format. A format is literal text around one run of
        # zeros, which pads the number to that width; a leading `<b>` makes it
        # bold. Without a format the number is bold and unpadded.
        class Numbering
          FORMAT = /\A(?<bold><b>)?(?<before>[^0<>#.]*)(?<zeros>0+)
                    (?<after>[^0<>#.]*)\z/x
          private_constant :FORMAT

          attr_reader :start, :step, :weight

          # @param format [String, nil] the text between the quotes
          # @return [Numbering, nil] nil when the format is not one read
          def self.read(start: 1, step: 1, format: nil)
            return new(start, step) unless format

            parts = FORMAT.match(format) or return
            new(start, step, parts, parts[:bold] ? "bold" : nil)
          end

          def initialize(start, step, parts = nil, weight = "bold")
            @start = start
            @step = step
            @parts = parts
            @weight = weight
            freeze
          end

          # @return [String] the text drawn for the `count`th number
          def text(count)
            return count.to_s unless @parts

            digits = count.to_s.rjust(@parts[:zeros].length, "0")
            "#{@parts[:before]}#{digits}#{@parts[:after]}"
          end
        end
      end
    end
  end
end
