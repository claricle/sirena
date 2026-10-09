# frozen_string_literal: true

require_relative "activation"
require_relative "bar_tracker"
require_relative "divider"
require_relative "fragment"
require_relative "message"
require_relative "note"
require_relative "fragment_shape"
require_relative "note_geometry"
require_relative "note_shape"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Walks the items of a diagram down the page and places each one,
        # given where the lifelines are. Rows are consumed from `y` downwards;
        # `left`, `right` and `y` describe the space the items ended up using.
        class Walker
          ROW = 40.0
          SELF_WIDTH = 36.0
          SELF_HEIGHT = 20.0
          ARROW_LENGTH = 10.0
          ARROW_HALF_WIDTH = 4.0
          TAB_HEIGHT = 20.0

          attr_reader :arrows, :notes, :fragments, :dividers, :left, :right, :y

          # @param lifelines [Hash{String => Float}] centre of each
          #   participant's lifeline, in participant order
          # @param measure [#call] text width in pixels
          # @param bounds [Array<Float>] left and right edge of the heads
          # @param start_y [Float] where the first row goes
          def initialize(lifelines:, measure:, font_size:, bounds:, start_y:)
            @ids = lifelines.keys
            @centers = lifelines.values
            @measure = measure
            @font_size = font_size
            @bounds = bounds
            @y = start_y
            start_empty
          end

          def run(items)
            previous = nil
            items.each do |item|
              @mark_y = nil unless anchoring?(item)
              visit(item, previous)
              previous = item
            end
            @tracker.finish(@y - 20)
            self
          end

          def bars
            @tracker.bars
          end

          private

          def start_empty
            @arrows = []
            @notes = []
            @fragments = []
            @dividers = []
            @tracker = BarTracker.new(method(:centre))
            @blocks = []
            @left = Float::INFINITY
            @right = -Float::INFINITY
          end

          def anchoring?(item)
            [Message, Activation].any? { |kind| item.is_a?(kind) }
          end

          def visit(item, previous)
            case item
            when Message then message(item)
            when Activation then activation(item)
            when Note then note(item, previous)
            when Fragment then fragment(item)
            else divider(item)
            end
          end

          def message(message)
            @last_y = @mark_y = @y
            from, to = [message.from, message.to].map { |id| centre(id) }
            @arrows << arrow_record(message, arrow_for(message, from, to))
            touch(*extent(message, from, to))
            @y += message.self_message? ? ROW * 1.5 : ROW
          end

          def extent(message, from, to)
            low, high = [from, to].minmax
            [low, high + (message.self_message? ? reach(message) : 0)]
          end

          # A bar starts or ends at the arrow it is written on, or else
          # between the rows on either side of the line.
          def activation(item)
            @tracker.apply(item, @mark_y || (@y - 20))
          end

          def arrow_for(message, from, to)
            message.self_message? ? self_arrow(from) : straight(from, to)
          end

          def centre(id)
            @centers.fetch(@ids.index(id))
          end

          def reach(message)
            SELF_WIDTH + 6 + @measure.call(message.label.to_s)
          end

          def straight(from, to)
            sign = to >= from ? 1 : -1
            { path: "M #{from} #{@y} L #{to} #{@y}", tip: [to, @y], dx: -sign,
              label: [(from + to) / 2, @y - 6, "middle"] }
          end

          def self_arrow(centre)
            right = centre + SELF_WIDTH
            bottom = @y + SELF_HEIGHT
            { path: "M #{centre} #{@y} L #{right} #{@y} L #{right} #{bottom} " \
                    "L #{centre} #{bottom}",
              tip: [centre, bottom], dx: 1,
              label: [right + 6, @y + 12, "start"] }
          end

          def arrow_record(message, geometry)
            Scene::Arrow.new(
              id: "message-#{@arrows.size + 1}", path: geometry[:path],
              dashed: message.dashed,
              marker_points: head_points(geometry[:tip], geometry[:dx]),
              marker_filled: message.head == :filled,
              texts: label_texts(message, geometry[:label])
            )
          end

          def head_points(tip, direction)
            x, y = tip
            back = x + (direction * ARROW_LENGTH)
            [[x, y], [back, y - ARROW_HALF_WIDTH],
             [back, y + ARROW_HALF_WIDTH]].map { |px, py| "#{px},#{py}" }
              .join(" ")
          end

          def label_texts(message, geometry)
            return [] unless message.label && !message.label.empty?

            x, y, anchor = geometry
            [text(message.label, x, y, "message_label", anchor)]
          end

          def text(content, at_x, at_y, role, anchor = "middle")
            PlantUML::Scene::Text.new(content: content, x: at_x, y: at_y,
                                      role: role, anchor: anchor)
          end

          def touch(low, high)
            @left = [@left, low].min
            @right = [@right, high].max
            return if @blocks.empty?

            @blocks.last[:low] = [@blocks.last[:low], low].min
            @blocks.last[:high] = [@blocks.last[:high], high].max
          end

          def note(note, previous)
            x, width = note_box(note, previous)
            height = NoteGeometry.height(note, @font_size)
            top = note.attached? ? @last_y - height + 10 : @y - 20
            @notes << note_record(note, [x, top, width, height])
            touch(x, x + width)
            @y = [@y, top + height + 22].max
          end

          def note_box(note, previous)
            span = NoteGeometry.span(note, previous, @ids)
            natural = NoteGeometry.natural_width(note, @measure)
            NoteGeometry.box(note, span.map { |i| @centers[i] }, natural)
          end

          def note_record(note, box)
            x, top, width, height = box
            Scene::Note.new(
              path: NoteShape.outline(note.shape, x, top, width, height),
              fold_path: NoteShape.fold(note.shape, x, top, width),
              texts: note_texts(note, x + NoteGeometry::PAD, top),
            )
          end

          def note_texts(note, left, top)
            step = NoteGeometry.line_height(@font_size)
            note.lines.each_with_index.map do |line, index|
              baseline = top + 7 + (index * step) + @font_size
              text(line, left, baseline, "note", "start")
            end
          end

          def fragment(item)
            case item.phase
            when :open then open_block(item)
            when :else then branch(item)
            else close_block
            end
          end

          def open_block(item)
            @blocks << { keyword: item.keyword, label: item.label.to_s,
                         top: @y - 20, low: Float::INFINITY,
                         high: -Float::INFINITY, branches: [], depth: 0 }
            @y += TAB_HEIGHT
          end

          def branch(item)
            @blocks.last[:branches] << [@y - 10, item.label.to_s]
            @y += 28
          end

          def close_block
            block = @blocks.pop
            bottom = @y - 20
            @y += 10
            emit_fragment(block, bottom)
          end

          def emit_fragment(block, bottom)
            record = FragmentShape.new(block, bottom, @centers, @measure)
            @fragments << record.scene
            touch(record.x, record.x + record.width)
            parent = @blocks.last
            parent[:depth] = [parent[:depth], block[:depth] + 1].max if parent
          end

          def divider(item)
            left, right = @bounds
            label = item.label.to_s
            @dividers << divider_record(label, left, right)
            @y += ROW
          end

          def divider_record(label, left, right)
            width = label.empty? ? 0.0 : @measure.call(label) + 20
            middle = (left + right) / 2
            Scene::Divider.new(
              lines: [-2, 2].map { |dy| segment(left, right, @y + dy) },
              x: middle - (width / 2), y: @y - 10, width: width, height: 20.0,
              texts: divider_texts(label, middle)
            )
          end

          def divider_texts(label, middle)
            label.empty? ? [] : [text(label, middle, @y + 5, "divider")]
          end

          def segment(left, right, at_y)
            PlantUML::Scene::Segment.new(x1: left, y1: at_y,
                                         x2: right, y2: at_y)
          end
        end
      end
    end
  end
end
