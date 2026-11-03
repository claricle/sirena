# frozen_string_literal: true

require_relative "block"
require_relative "markup"
require_relative "row"
require_relative "widget"

module Sirena
  module Notation
    module PlantUMLSalt
      # Reads `@startsalt ... @endsalt` into a {Block} tree. Anything it does
      # not recognise becomes plain text; it never raises on content.
      class Parser
        OPENER = /\A\{([#+!\-^*TS]*)(?:[ \t]+(.*))?\z/
        START = /\A@startsalt(?![A-Za-z0-9_])/
        FINISH = /\A@endsalt\b/
        CHECKBOX = /\A\[([xX ]?)\](?:[ \t]+(.*))?\z/
        RADIO = /\A\(([xX ]?)\)(?:[ \t]+(.*))?\z/
        BUTTON = /\A\[([^\]]+)\]\z/
        FIELD = /\A"(.*)"\z/
        DROPLIST = /\A\^(.*)\^\z/
        private_constant :OPENER, :START, :FINISH, :CHECKBOX, :RADIO,
                         :BUTTON, :FIELD, :DROPLIST

        # @param source [String] any String; invalid UTF-8 is scrubbed
        # @return [Block] a root block holding every top-level row
        def parse(source)
          @root = Block.new("")
          @stack = [@root]
          body(source).each { |line| read_line(line) }
          @root
        end

        private

        def body(source)
          text = source.dup.force_encoding(Encoding::UTF_8).scrub
          lines = text.delete_prefix("\uFEFF").lines.map(&:strip)
          inside(lines).reject(&:empty?)
        end

        # What lies between `@startsalt` and `@endsalt`, either of which
        # may be absent.
        def inside(lines)
          from = lines.index { |line| START.match?(line) }
          lines = lines.drop(from + 1) if from
          stop = lines.index { |line| FINISH.match?(line) }
          stop ? lines.first(stop) : lines
        end

        def read_line(line)
          while (match = OPENER.match(line))
            open_block(match[1])
            line = match[2].to_s.strip
          end
          line, closers = strip_closers(line)
          add_row(line) unless line.empty?
          closers.times { close_block }
        end

        def strip_closers(line)
          closers = 0
          while line.start_with?("}") || closing_group?(line)
            line = line.delete_prefix("}").chomp("}").strip
            closers += 1
          end
          [line, closers]
        end

        def closing_group?(line)
          line.end_with?("}") && line.start_with?("{")
        end

        def open_block(modifier)
          block = Block.new(modifier)
          @stack.last.rows << Row.new([block])
          @stack.push(block)
        end

        def close_block
          @stack.pop if @stack.size > 1
        end

        def add_row(line)
          block = @stack.last
          depth, line = nesting(block, line)
          cells = line.split("|", -1).map { |cell| widget(cell.strip) }
          block.rows << Row.new(cells, depth: depth)
        end

        # The depth a tree row's leading `+` marks give it, and the rest.
        def nesting(block, line)
          marks = block.tree? ? line[/\A\+*/] : ""
          [marks.length, line.delete_prefix(marks).strip]
        end

        def widget(text)
          return Widget.new(:empty) if text.empty? || text == "."

          labelled(text) || Widget.new(:text, Markup.runs(text))
        end

        def labelled(text)
          toggle(:checkbox, CHECKBOX.match(text)) ||
            toggle(:radio, RADIO.match(text)) ||
            styled(:button, BUTTON.match(text)) ||
            styled(:field, FIELD.match(text)) ||
            droplist(DROPLIST.match(text))
        end

        def toggle(kind, match)
          return unless match

          Widget.new(kind, Markup.runs(match[2].to_s),
                     checked: !match[1].strip.empty?)
        end

        def styled(kind, match)
          Widget.new(kind, Markup.runs(match[1].strip)) if match
        end

        def droplist(match)
          return unless match

          Widget.new(:droplist, Markup.runs(match[1].split("^").first.to_s))
        end
      end
    end
  end
end
