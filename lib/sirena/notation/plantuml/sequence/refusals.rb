# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Names the construct on a sequence line the parser does not read, for
        # the error message. Asked only after the parser has refused a line.
        module Refusals
          extend self

          WORDS = %w[
            note hnote rnote group alt else opt loop par par2 critical break
            end box endbox activate deactivate destroy create return
            autonumber newpage ref title header footer hide show skinparam
            legend caption participant actor boundary control entity database
            collections queue
          ].freeze
          LEADING = /\A(#{WORDS.join('|')})\b/io
          RULES = [
            [LEADING, nil],
            [/\A(?:left|right|center)[ \t]+(?:header|footer)\b/i,
             "aligned header or footer"],
            [/\A!/, "preprocessor directive"],
            [/\A<style\b/i, "style block"],
            [/\A==.*==\z/, "divider"],
            [/\A\.\.\./, "delay"],
            [/\A\|\|\|/, "spacing"],
            [/\A&/, "parallel message"],
            [/\A\}/, "closing brace"],
            [%r{-+>|<-+|-\[|-[\\/]|[/\\]-}, "message arrow"],
          ].freeze
          private_constant :WORDS, :LEADING, :RULES

          # @return [String] the construct's name, "statement" when unknown
          def name_for(text)
            RULES.each do |pattern, name|
              match = pattern.match(text)
              return name || match[1].downcase if match
            end
            "statement"
          end
        end
      end
    end
  end
end
