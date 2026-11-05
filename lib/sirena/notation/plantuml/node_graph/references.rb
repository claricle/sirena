# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The patterns that name a node in a link or a declaration.
        module References
          IDENT = /[\p{L}\p{N}_$]+/
          BRACKET = /\[[^\]]+\]|\([^()]*\)|:[^:\n]+:/
          REF = /#{BRACKET}|"[^"]+"|#{IDENT}/
          DIRECTION = /(?:up|down|left|right)(?![[:alpha:]])/
          ARROW = /<?<?[-.=]+(?:\[[^\]]*\]|#{DIRECTION})?
                   [-.=]*(?:\(0\)|\(0|0\)|\))?[-.=]*>?>?/x
          EDGE = /\A(?<a>#{REF})\s*(?<arrow>#{ARROW})\s*(?<b>#{REF})
                  (?:\s*:\s*(?<label>.*))?\z/x
          ER_LEFT = /\|o|\|\||\}o|\}\|/
          ER_RIGHT = /o\||\|\||o\{|\|\{/
          ER_EDGE = /\A(?<a>#{REF})\s+(?<l>#{ER_LEFT})(?<line>[-.]+)
                     (?<r>#{ER_RIGHT})\s+(?<b>#{REF})
                     (?:\s*:\s*(?<label>.*))?\z/x
          STEREOTYPE = /<<\s*(?<st>.*?)\s*>>/
          LEADING_COLOR = /\A\#(?<color>[0-9A-Fa-f]{3,8}|[A-Za-z]+)\s+/
          COLOR = /\s+#(?<color>[0-9A-Fa-f]{3,8}|[A-Za-z]+)\z/

          module_function

          # @return [Array<String>] the lines of a label
          def lines_of(text)
            lines = text.to_s.split(/\\n|\n/).map(&:strip)
            lines.empty? ? [""] : lines
          end
        end
      end
    end
  end
end
