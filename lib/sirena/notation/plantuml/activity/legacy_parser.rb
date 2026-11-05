# frozen_string_literal: true

require_relative "builder"
require_relative "text"
require_relative "arrow_style"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Reads the legacy syntax: `(*) --> "Action"` arrows between named
        # activities, with `if` ... `else` ... `endif`. A direction hint such
        # as `-left->` is a layout hint and is not kept. The node the flow is
        # at is `@current`; an arrow with no source starts there.
        #
        # PlantUML's own reader is followed where it differs from the new
        # syntax: the flow after `endif` is the last node the branch drew
        # (no join, no merge node), `(*)` is a node the flow can leave, and
        # a quoted activity written twice is one node. An arrow `->`, or one
        # with `-right->` or `-left->`, lies along its row.
        class LegacyParser
          ARROW = /-+(?:\[[^\]]*\]|left|right|up|down)?-*>/
          STATEMENT = /\A(?<source>\(\*(?:top)?\)|"[^"]*"|={2,}[^=]+={2,}|\w+)?
                       \s*(?<arrow>#{ARROW})\s*(?:\[(?<label>[^\]]*)\])?
                       \s*(?<dest>.+?)\s*\z/xm
          IF = /\Aif\s+(?:"(?<cond>.*)"|\((?<paren>.*)\))\s+then\z/i
          TITLE = /\Atitle\s+(.+)\z/i
          BAR = /\A={2,}\s*(.+?)\s*={2,}\z/
          ACTIVITY = /\A"(.*)"(?:\s+as\s+(\w+))?\z/m
          private_constant :TITLE, :ARROW, :STATEMENT, :IF, :BAR, :ACTIVITY

          # @param entries [Array<Array(String, Integer)>] lines and numbers
          # @return [Diagram]
          def parse(entries)
            reset
            join_quoted(entries).each { |line, number| statement(line, number) }
            refuse("unclosed if", "") unless @frames.empty?
            @builder.diagram
          end

          private

          def reset
            @builder = Builder.new
            @current = nil
            @stop = nil
            @frames = []
            @names = {}
            @labels = {}
            @bars = {}
          end

          # A quoted activity may run over several lines.
          def join_quoted(entries)
            entries.each_with_object([]) do |(line, number), joined|
              open_entry = joined.last
              if open_entry && open_entry[0].count('"').odd?
                open_entry[0] = "#{open_entry[0]}\n#{line}"
              else
                joined << [line, number]
              end
            end
          end

          def statement(line, number)
            @number = number
            @line = line
            case line
            when TITLE then @builder.title = clean(Regexp.last_match(1))
            when IF then open_if(Regexp.last_match)
            when /\Aelse\z/i then open_else
            when /\Aendif\z/i then close_if
            when STATEMENT then flow(Regexp.last_match)
            else refuse("statement", line)
            end
          end

          def open_if(match)
            text = clean(match[:cond] || match[:paren])
            decision = legacy(@builder.node(:decision, text: text))
            @builder.connect(@current, decision) if @current
            @frames << decision
            @current = decision
          end

          def open_else
            @current = top
          end

          # The flow carries on from the last node the closing branch drew.
          def close_if
            top
            @frames.pop
          end

          def legacy(node)
            node.tap { |item| item.legacy = true }
          end

          def flow(match)
            from = source_of(match)
            style = ArrowStyle.parse(match[:arrow][/\[([^\]]*)\]/, 1],
                                     line: @number)
            dest = destination(match[:dest])
            edge = @builder.connect(from, dest,
                                    label: arrow_label(match[:label]), **style)
            edge.direction = direction(match[:arrow])
            @current = dest
          end

          def direction(arrow)
            return :right if arrow == "->"

            arrow[/left|right/]&.to_sym
          end

          # The node an arrow leaves: the one written, else wherever the
          # flow is.
          def source_of(match)
            written = match[:source]
            return resolve(written) if written

            @current or refuse("arrow without a source", @line)
          end

          def arrow_label(label)
            label && clean(label)
          end

          def resolve(source)
            case source
            when /\A\(\*(?:top)?\)\z/ then @builder.node(:start)
            when /\A"/ then activity(source)
            when BAR then bar(Regexp.last_match(1))
            else @names.fetch(source) do
                   refuse("undefined activity #{source}", @line)
                 end
            end
          end

          def destination(text)
            return (@stop ||= @builder.node(:stop)) if
              text.match?(/\A\(\*(?:top)?\)\z/)
            return bar(Regexp.last_match(1)) if text.match(BAR)
            return activity(text) if text.start_with?('"')

            @names.fetch(text) { refuse("undefined activity #{text}", @line) }
          end

          def activity(text)
            match = ACTIVITY.match(text) or refuse("activity", text)
            return @labels[match[1]] ||= action(match[1]) unless match[2]

            @names[match[2]] = action(match[1])
          end

          def action(text)
            @builder.node(:action, text: clean(text))
          end

          def bar(name)
            @bars[name] ||= legacy(@builder.node(:bar, text: name))
          end

          def top
            @frames.last or refuse("else/endif without if", @line)
          end

          def clean(text)
            Text.clean(text, line: @number)
          end

          def refuse(construct, text)
            raise UnsupportedConstructError.new(construct: construct,
                                                line: @number, text: text)
          end
        end
      end
    end
  end
end
