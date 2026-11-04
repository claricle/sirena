# frozen_string_literal: true

require_relative "../unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Reads the `[#blue,dashed]` part of an arrow.
        module ArrowStyle
          module_function

          STYLES = { "dashed" => :dashed, "dotted" => :dotted,
                     "bold" => :bold, "plain" => nil }.freeze
          HEX = /\A(?:\h{3}|\h{6})\z/
          private_constant :STYLES, :HEX

          # @return [Hash] `:colour` and `:style`, either possibly nil
          def parse(spec, line:)
            result = { colour: nil, style: nil }
            spec.to_s.split(",").map(&:strip).each do |word|
              apply(result, word, line, spec)
            end
            result
          end

          # `#pink` is a colour name, `#ccf` and `#33668E` are hex.
          # @return [String, nil]
          def colour(word)
            name = word.delete_prefix("#")
            return nil if name.empty?

            HEX.match?(name) ? "##{name}" : name
          end

          def apply(result, word, line, spec)
            if word.start_with?("#")
              result[:colour] = colour(word)
            elsif STYLES.key?(word.downcase)
              result[:style] = STYLES.fetch(word.downcase)
            else
              raise UnsupportedConstructError.new(
                construct: "arrow style #{word.inspect}", line: line,
                text: spec
              )
            end
          end
          private_class_method :apply
        end
      end
    end
  end
end
