# frozen_string_literal: true

require_relative "builder"
require_relative "text"
require_relative "arrow_style"
require_relative "new_parser/blocks"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Reads the new activity syntax: `start`, `:action;`, `if` ...
        # `endif`, `while`, `repeat`, `switch`, `fork`, partitions, swimlanes
        # and notes. The open ends of the flow are kept in `@ends` as
        # [node, label] pairs; a `stop` leaves none.
        class NewParser
          include Blocks

          SIMPLE = [
            [/\Astart\z/i, :on_start],
            [/\A(?:stop|end)\z/i, :on_stop],
            [/\Atitle\s+(.+)\z/i, :on_title],
            [/\A(?<colour>#\w+)?:(?<text>.*)\z/m, :on_action],
            [/\A-+(?:\[(?<spec>[^\]]*)\])?-*>\s*(?<text>.*)\z/m, :on_arrow],
            [/\A\|(?:(?<colour>#\w+)\|)?(?<name>[^|]+)\|\z/, :on_lane],
            [/\Anote\s+(?<side>left|right)\s*(?:of\s+\S+\s*)?
             (?::(?<text>.*))?\z/xi, :on_note],
            [/\Apartition\s+(?<name>.*?)\s*\{\z/i, :on_partition],
            [/\A\}\z/, :on_close_partition],
          ].freeze
          STATEMENTS = (SIMPLE + Blocks::PATTERNS).freeze
          private_constant :SIMPLE, :STATEMENTS

          # @param entries [Array<Array(String, Integer)>] lines and numbers
          # @return [Diagram]
          def parse(entries)
            @builder = Builder.new
            @ends = []
            @frames = []
            @arrow = {}
            @entries = entries.each
            loop { statement(*@entries.next) }
            refuse("unclosed #{@frames.last[:kind]}", @line) if @frames.any?
            @builder.diagram
          end

          private

          def statement(line, number)
            @line = line
            @number = number
            STATEMENTS.each do |pattern, handler|
              match = pattern.match(line)
              return send(handler, match) if match
            end
            refuse("statement", line)
          end

          def on_start(_match)
            add(@builder.node(:start))
          end

          def on_stop(_match)
            add(@builder.node(:stop))
            @ends = []
          end

          def on_title(match)
            @builder.title = clean(match[1])
          end

          def on_action(match)
            fill = ArrowStyle.colour(match[:colour]) if match[:colour]
            text = clean(collect(match[:text]))
            add(@builder.node(:action, text: text, fill: fill))
          end

          def on_arrow(match)
            @arrow = ArrowStyle.parse(match[:spec], line: @number)
            text = match[:text]
            @arrow[:label] = text.empty? ? nil : clean(collect(text))
          end

          def on_lane(match)
            colour = match[:colour] && ArrowStyle.colour(match[:colour])
            @builder.lane(match[:name].strip, colour)
          end

          def on_note(match)
            text = match[:text] ? match[:text].strip : collect_note
            node = @builder.nodes.last
            refuse("note without a preceding activity", @line) unless node
            node.notes << Note.new(side: match[:side].downcase.to_sym,
                                   text: clean(text))
          end

          def on_partition(match)
            title = match[:name].gsub(/#\w+/, "").delete('"').strip
            @builder.partition(title, line: @number, text: @line)
          end

          def on_close_partition(_match)
            @builder.partition(nil)
          end

          # Text that runs to the next line ending in `;`.
          def collect(first)
            text = first.dup
            text << "\n" << next_line until text.end_with?(";")
            text.chomp(";")
          end

          def collect_note
            lines = []
            while (line = next_line) && !line.match?(/\Aend\s*note\z/i)
              lines << line
            end
            lines.join("\n")
          end

          def next_line
            @entries.next.first
          rescue StopIteration
            refuse("unterminated activity (missing `;`)", @line)
          end

          # Joins every open end to the new node, then makes it the only
          # open end.
          def add(node)
            @ends.each do |from, label|
              @builder.connect(from, node, **edge_options(label))
            end
            @arrow = {}
            @ends = [[node, nil]]
            node
          end

          def edge_options(label)
            { label: @arrow[:label] || label, colour: @arrow[:colour],
              style: @arrow[:style] }
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
