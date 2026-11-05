# frozen_string_literal: true

require "strscan"
require_relative "../state/reader"
require_relative "../../../error/parse_error"
require_relative "model"

module Sirena
  module Notation
    module PlantUML
      module Ebnf
        # Reads `name = expression ;` rules in the ISO EBNF notation:
        # `,` sequence, `|` choice, `[ ]` optional, `{ }` repetition (`{ }-`
        # one or more), `( )` grouping, quoted terminals, `? ?` special
        # sequences and `(* *)` comments. Anything else raises
        # {Sirena::Parser::ParseError}.
        class Reader
          TOKEN = /\s*(?:(?<string>"[^"]*"|'[^']*')|(?<special>\?[^?]*\?)|
                   (?<name>[A-Za-z_]\w*(?:[ \t]+[A-Za-z_]\w*)*)|
                   (?<mark>[=,|;\[\]{}()-]))/xm
          COMMENT = /\(\*.*?\*\)/m
          private_constant :TOKEN, :COMMENT

          # @param source [String] PlantUML source
          # @return [Array<Rule>]
          def parse(source)
            body = State::Reader.lines_of(source).map(&:first).join("\n")
            @tokens = tokenize(body.gsub(COMMENT, " "))
            rules = []
            rules << rule until @tokens.empty?
            raise fail_with("no rule found") if rules.empty?

            rules
          end

          private

          def tokenize(text)
            tokens = []
            scanner = StringScanner.new(text)
            until scanner.skip(/\s*\z/)
              unless scanner.scan(TOKEN)
                raise fail_with("cannot read #{scanner.rest[0,
                                                            20].inspect}")
              end

              tokens << token_of(scanner)
            end
            tokens
          end

          def token_of(scanner)
            %i[string special name mark].each do |kind|
              value = scanner[kind]
              return [kind, value.strip] if value
            end
          end

          def rule
            name = take(:name)
            take(:mark, "=")
            expression = choice
            take(:mark, ";")
            Rule.new(name: name, expression: expression)
          end

          def choice
            branches = [sequence]
            branches << sequence while consume?("|")
            branches.one? ? branches.first : Choice.new(branches: branches)
          end

          def sequence
            items = [term]
            items << term while consume?(",")
            items.one? ? items.first : Sequence.new(items: items)
          end

          def term
            kind, value = @tokens.shift
            case kind
            when :string then Literal.new(text: value[1..-2])
            when :special then Special.new(text: value[1..-2].strip)
            when :name then Reference.new(name: value)
            when :mark then bracketed(value)
            else raise fail_with("unexpected end of rule")
            end
          end

          def bracketed(mark)
            case mark
            when "[" then Optional.new(item: closed(choice, "]"))
            when "{" then repetition
            when "(" then closed(choice, ")")
            else raise fail_with("unexpected #{mark.inspect}")
            end
          end

          def repetition
            item = closed(choice, "}")
            Repetition.new(item: item, least: consume?("-") ? 1 : 0)
          end

          def closed(node, mark)
            take(:mark, mark)
            node
          end

          def consume?(mark)
            return false unless @tokens.first == [:mark, mark]

            @tokens.shift
            true
          end

          def take(kind, value = nil)
            token = @tokens.shift
            return token[1] if token && token[0] == kind &&
              (value.nil? || token[1] == value)

            raise fail_with("expected #{value || kind}")
          end

          def fail_with(message)
            Sirena::Parser::ParseError.new("EBNF: #{message}")
          end
        end
      end
    end
  end
end
