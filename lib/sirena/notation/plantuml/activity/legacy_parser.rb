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
            decision = legacy(@builder.node(:decision, text: text, bare: true))
            joined(decision)
            @frames << { decision: decision, tails: [], else: false }
            @current = decision
          end

          def open_else
            frame = top
            frame[:tails].concat(Array(@current))
            frame[:else] = true
            @current = frame[:decision]
          end

          def close_if
            frame = top
            @frames.pop
            tails = frame[:tails]
            tails.concat(Array(@current))
            tails << frame[:decision] unless frame[:else]
            tails.uniq!
            @current = tails.one? ? tails.first : (tails unless tails.empty?)
          end

          # The legacy syntax draws no node where the branches of an `if`
          # meet: each of them runs on into whatever follows.
          def joined(node)
            Array(@current).each { |tail| @builder.connect(tail, node) }
          end

          def legacy(node)
            node.tap { |item| item.legacy = true }
          end

          def flow(match)
            sources = sources_of(match)
            style = ArrowStyle.parse(match[:arrow][/\[([^\]]*)\]/, 1],
                                     line: @number)
            dest = destination(match[:dest])
            label = arrow_label(match[:label])
            sources.each do |from|
              @builder.connect(from, dest, label: label, **style)
            end
            @current = dest.kind == :stop ? nil : dest
          end

          # The nodes an arrow leaves: the one written, else wherever the
          # flow is, which after an `endif` is every branch that is live.
          def sources_of(match)
            written = match[:source]
            sources = written ? [resolve(written)] : Array(@current)
            refuse("arrow without a source", @line) if sources.empty?
            sources
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
            node = @builder.node(:action, text: clean(match[1]))
            @names[match[2]] = node if match[2]
            node
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
