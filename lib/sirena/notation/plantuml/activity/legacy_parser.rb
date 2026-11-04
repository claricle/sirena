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
            decision = @builder.node(:decision, text: text)
            @builder.connect(@current, decision) if @current
            @frames << { decision: decision, tails: [], else: false }
            @current = decision
          end

          def open_else
            frame = top
            frame[:tails] << @current if @current
            frame[:else] = true
            @current = frame[:decision]
          end

          def close_if
            frame = top
            @frames.pop
            tails = frame[:tails]
            tails << @current if @current
            tails << frame[:decision] unless frame[:else]
            tails.uniq!
            @current = merged(tails)
          end

          def merged(tails)
            return nil if tails.empty?
            return tails.first if tails.one?

            @builder.node(:merge).tap do |merge|
              tails.each { |tail| @builder.connect(tail, merge) }
            end
          end

          def flow(match)
            source = match[:source] ? resolve(match[:source]) : @current
            refuse("arrow without a source", @line) unless source
            style = ArrowStyle.parse(match[:arrow][/\[([^\]]*)\]/, 1],
                                     line: @number)
            dest = destination(match[:dest])
            @builder.connect(source, dest, label: arrow_label(match[:label]),
                                           **style)
            @current = dest.kind == :stop ? nil : dest
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
            return @builder.node(:stop) if text.match?(/\A\(\*(?:top)?\)\z/)
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
            @bars[name] ||= @builder.node(:bar, text: name)
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
