# frozen_string_literal: true

require_relative "block"
require_relative "markup"
require_relative "row"
require_relative "run"
require_relative "widget"

module Sirena
  module Notation
    module PlantUMLSalt
      # Reads `@startsalt ... @endsalt` into a {Block} tree. Anything it does
      # not recognise becomes plain text; it never raises on content.
      class Parser
        OPENER = %r{\A\{((?:S[I-]?)?[#+!\-*T/]*)(?:[ \t]+(.*))?\z}
        # `{^Title`: the rest of the line heads the box.
        TITLED = /\A\{\^(.*)\z/
        START = /\A@startsalt(?![A-Za-z0-9_])/
        CLOSE_TAIL = /\A\}\s*\|(.*)\z/
        FINISH = /\A@endsalt\b/
        INLINE_CLOSE = /\A([^{}]*?)\s*\}\s*\|(.*)\z/
        CHECKBOX = /\A\[([xX ]?)\](?:[ \t]+(.*))?\z/
        RADIO = /\A\(([xX ]?)\)(?:[ \t]+(.*))?\z/
        BUTTON = /\A\[([^\]]+)\]\z/
        FIELD = /\A"(.*)"\z/
        DROPLIST = /\A\^(.*)\^\z/
        # A line of its own: `..`, `==`, `--` or `~~`, which may carry a
        # title closed by the same mark (`.. title ..`, dropped on draw).
        RULE = /\A(\.\.|==|--|~~)(?:.*?\1)?\z/
        RULE_VARIANTS = { ".." => :dotted, "==" => :double, "--" => :solid,
                          "~~" => :heavy }.freeze
        # `== Title`: a bold heading in the row's first cell.
        HEADING = /\A==\s*(\S.*)\z/
        HEADING_SIZE = 14
        private_constant :OPENER, :TITLED, :CLOSE_TAIL, :START, :FINISH,
                         :CHECKBOX, :RADIO, :BUTTON, :FIELD, :DROPLIST,
                         :INLINE_CLOSE, :RULE, :RULE_VARIANTS, :HEADING,
                         :HEADING_SIZE

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
          line, opened = open_blocks(line)
          return if opened && inline_closed?(line)
          return if closed_with_tail?(line)

          line, closers = strip_closers(line)
          add_row(line) unless line.empty?
          closers.times { close_block }
        end

        # Opens every group the line starts with.
        # @return [Array(String, Boolean)] what follows them and whether any
        #   opened
        def open_blocks(line)
          opened = false
          while (rest = open_block_on(line))
            line = rest
            opened = true
          end
          [line, opened]
        end

        # @return [String, nil] what follows the opener, nil when there is none
        def open_block_on(line)
          if (titled = TITLED.match(line))
            open_block("^", title: heading_runs(titled[1].strip))
            return ""
          end
          match = OPENER.match(line) or return

          open_block(match[1])
          match[2].to_s.strip
        end

        def heading_runs(text)
          Markup.runs(text) unless text.empty?
        end

        # `{+ a | b } | c`: the block closes mid-line and `c` joins the
        # row that holds the block.
        def inline_closed?(line)
          match = INLINE_CLOSE.match(line) or return false

          add_row(match[1]) unless match[1].empty?
          close_block
          graft(match[2])
          true
        end

        # `} | c`: the block closes and `c` joins the row that holds it.
        def closed_with_tail?(line)
          match = CLOSE_TAIL.match(line) or return false

          close_block
          graft(match[1])
          true
        end

        def graft(tail)
          host = @stack.last
          row = host.rows.pop
          cells = tail.split("|", -1).map { |cell| widget(cell.strip) }
          host.rows << Row.new(row.cells + cells, depth: row.depth)
        end

        def strip_closers(line)
          closers = 0
          while line.start_with?("}") || closing_group?(line) ||
              closing_row?(line)
            line = line.delete_prefix("}").chomp("}").strip
            closers += 1
          end
          [line, closers]
        end

        # `+ World }`: the `}` that ends a row closes the block holding it.
        def closing_row?(line)
          line.end_with?("}") && !line.include?("{")
        end

        def closing_group?(line)
          line.end_with?("}") && line.start_with?("{")
        end

        def open_block(modifier, **)
          block = Block.new(modifier, **)
          @stack.last.rows << Row.new([block])
          @stack.push(block)
        end

        def close_block
          @stack.pop if @stack.size > 1
        end

        def add_row(line)
          block = @stack.last
          depth, line = nesting(block, line)
          cells = (rule(line) unless block.tree?) || cells(line, block)
          block.rows << Row.new(cells, depth: depth)
        end

        def rule(line)
          match = RULE.match(line) or return

          [Widget.new(:rule, variant: RULE_VARIANTS.fetch(match[1]))]
        end

        def cells(line, block)
          cells = line.delete_prefix("|").split("|", -1)
            .map { |cell| widget(cell.strip, tree: block.tree?) }
          titled = HEADING.match(line) unless block.tree?
          cells[0] = heading(titled[1]) if titled
          cells
        end

        # The first cell's text, set as a heading in place of its `==`.
        def heading(text)
          title = text.split("|", 2).first.strip
          Widget.new(:text, [Run.new(title, bold: true, size: HEADING_SIZE)])
        end

        # The depth a tree row's leading `+` marks give it, and the rest.
        def nesting(block, line)
          marks = block.tree? ? line[/\A\+*/] : ""
          [marks.length, line.delete_prefix(marks).strip]
        end

        # In a tree table a quoted cell is the text itself, quotes
        # included; elsewhere it is a text field.
        def widget(text, tree: false)
          return Widget.new(:empty) if text.empty?
          return Widget.new(:empty, [Run.new(text)]) if text == "."

          plain = tree && FIELD.match?(text)
          (labelled(text) unless plain) || Widget.new(:text, Markup.runs(text))
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
          labelled_widget(kind, match[1]) if match
        end

        # A label's spaces count toward the widget's size, not its text.
        def labelled_widget(kind, label, **extra)
          Widget.new(kind, Markup.runs(label.strip), **extra,
                     chars: Markup.runs(label).sum { |run| run.text.length })
        end

        def droplist(match)
          return unless match

          label, *items = match[1].split("^")
          items.reject! { |item| item.strip.empty? }
          labelled_widget(:droplist, label.to_s,
                          items: items.map { |item| Markup.runs(item) })
        end
      end
    end
  end
end
