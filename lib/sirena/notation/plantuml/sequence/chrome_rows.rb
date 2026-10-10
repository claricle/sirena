# frozen_string_literal: true

require_relative "chrome"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Sizes and places the title, header, caption, footer and legend of
        # a sequence diagram. The constants are the rows PlantUML draws for
        # them: `lead` is the room a text takes beyond its lines, `base` the
        # first baseline below the row's top and `step` the line height.
        class ChromeRows
          LINE = 16.49
          STYLES = {
            header: { step: 11.78, lead: 1.0, base: 9.67, anchor: "end",
                      size: 10.0, colour: "#888888", pad: 0.0 },
            title: { step: LINE, lead: 21.0, base: 23.54, anchor: "middle",
                     pad: 10.0 },
            caption: { step: LINE, lead: 3.0, base: 16.54, anchor: "middle",
                       pad: 2.0 },
            footer: { step: 11.78, lead: 1.0, base: 11.67, anchor: "middle",
                      size: 10.0, colour: "#888888", pad: 0.0 },
          }.freeze
          LEGEND_BEFORE = { top: 12.0, bottom: 14.0 }.freeze
          LEGEND_AFTER = { top: 13.0, bottom: 11.0 }.freeze
          LEGEND_BOX = 10.0
          LEGEND_SIDE = 12.0
          LEGEND_PAD = 5.0
          LEGEND_BASE = 18.54

          # @param diagram [Diagram]
          # @param measure [#call] width of a text given the text and a size
          def initialize(diagram, measure)
            @diagram = diagram
            @chrome = diagram.chrome
            @measure = measure
          end

          # @return [Float] what a kind pushes the rest of the diagram by
          def room(kind)
            count = lines(kind).size
            return 0.0 if count.zero?

            STYLES.fetch(kind)[:lead] + (STYLES.fetch(kind)[:step] * count)
          end

          # @return [Float] the room above the participants
          def top_room
            room(:header) + room(:title) + legend_room(:top)
          end

          # @return [Float] the room below the participants
          def bottom_room
            legend_room(:bottom) + room(:caption) + room(:footer)
          end

          # @return [Float] the width the texts need on their own
          def width
            kinds = STYLES.keys.map { |kind| text_width(kind) }
            [*kinds, legend_width + (2 * LEGEND_SIDE)].max
          end

          # @param top [Float] where the rows above the participants start
          # @param bottom [Float] where the participants end
          # @param canvas [Float] the width the texts are placed in
          # @return [Array<Scene::TextBlock>] the header, caption and footer
          #   that are written, each with its placed lines
          def blocks(top, bottom, canvas)
            tops = row_tops(top, bottom)
            %i[header caption footer].filter_map do |kind|
              next if lines(kind).empty?

              Scene::TextBlock.new(id: kind.to_s,
                                   texts: texts(kind, tops[kind], canvas))
            end
          end

          # @param top [Float] where the rows above the participants start
          # @return [Scene::Title, nil]
          def title(top, canvas)
            return if lines(:title).empty?

            Scene::Title.new(
              texts: texts(:title, top + room(:header), canvas),
            )
          end

          # @param top [Float] where the rows above the participants start
          # @param bottom [Float] where the participants end
          # @return [Scene::Legend, nil]
          def legend(top, bottom, canvas)
            return if lines(:legend).empty?

            edge = @chrome.legend_edge
            above = top + room(:header) + room(:title)
            start = edge == :top ? above : bottom
            box(start + LEGEND_BEFORE.fetch(edge), canvas)
          end

          # @return [Array<String>] the lines of one kind, empty if unset
          def lines(kind)
            return @diagram.title.to_s.split("\n") if kind == :title

            @chrome.lines(kind)
          end

          private

          def row_tops(top, bottom)
            caption = bottom + legend_room(:bottom)
            { header: top, title: top + room(:header), caption: caption,
              footer: caption + room(:caption) }
          end

          def texts(kind, top, canvas)
            style = STYLES.fetch(kind)
            lines(kind).each_with_index.map do |line, index|
              text = style.slice(:anchor, :colour, :size)
              y = top + style[:base] + (style[:step] * index)
              PlantUML::Scene::Text.new(content: line, role: kind.to_s,
                                        x: anchor_x(style, canvas), y: y,
                                        **text)
            end
          end

          def anchor_x(style, canvas)
            style[:anchor] == "end" ? canvas : canvas / 2
          end

          def text_width(kind)
            style = STYLES.fetch(kind)
            widest = lines(kind).map { |l| @measure.call(l, style[:size]) }.max
            widest ? widest + style[:pad] : 0.0
          end

          def legend_height
            LEGEND_BOX + (LINE * lines(:legend).size)
          end

          def legend_room(edge)
            return 0.0 if lines(:legend).empty? || @chrome.legend_edge != edge

            LEGEND_BEFORE.fetch(edge) + legend_height + LEGEND_AFTER.fetch(edge)
          end

          def legend_width
            widest = lines(:legend).map { |line| @measure.call(line, nil) }.max
            widest ? widest + (2 * LEGEND_PAD) : 0.0
          end

          def box(top, canvas)
            left = legend_left(canvas)
            Scene::Legend.new(
              x: left, y: top, width: legend_width, height: legend_height,
              texts: legend_texts(left + LEGEND_PAD, top)
            )
          end

          def legend_left(canvas)
            case @chrome.legend_side
            when :left then LEGEND_SIDE
            when :right then canvas - LEGEND_SIDE - legend_width
            else (canvas - legend_width) / 2
            end
          end

          def legend_texts(left, top)
            lines(:legend).each_with_index.map do |line, index|
              PlantUML::Scene::Text.new(
                content: line, role: "legend", x: left,
                y: top + LEGEND_BASE + (LINE * index), anchor: "start"
              )
            end
          end
        end
      end
    end
  end
end
