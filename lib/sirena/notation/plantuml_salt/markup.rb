# frozen_string_literal: true

require "strscan"
require_relative "run"

module Sirena
  module Notation
    module PlantUMLSalt
      # Reads the inline markup salt shares with Creole: `<b>`, `<i>`,
      # `<u>`, `<s>` and `<color:...>`. Any other angle-bracket text, such
      # as `<P>`, is kept as literal text.
      module Markup
        TAG = %r{<(/?)(b|i|u|s|color)(?::([#\w]+))?>}i
        UNTIL_TAG = /(?=#{TAG})|\z/
        STYLE_KEYS = { "b" => :bold, "i" => :italic, "u" => :underline,
                       "s" => :strike }.freeze
        private_constant :TAG, :UNTIL_TAG, :STYLE_KEYS

        module_function

        # @param text [String]
        # @return [Array<Run>] the styled runs, in source order
        def runs(text)
          state = {}
          scanner = StringScanner.new(text)
          found = []
          until scanner.eos?
            if scanner.scan(TAG) then apply(state, scanner)
            else found << Run.new(scanner.scan_until(UNTIL_TAG), **state)
            end
          end
          found
        end

        def apply(state, scanner)
          key = STYLE_KEYS.fetch(scanner[2].downcase, :color)
          if scanner[1].empty?
            state[key] = key == :color ? scanner[3] : true
          else
            state.delete(key)
          end
        end
      end
    end
  end
end
