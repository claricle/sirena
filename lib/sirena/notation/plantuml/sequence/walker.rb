# frozen_string_literal: true

require_relative "activation"
require_relative "arrow_marks"
require_relative "bar_tracker"
require_relative "destroy"
require_relative "divider"
require_relative "edge"
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
          TAB_HEIGHT = 20.0
          CROSS_HALF = 9.0
          TOP_OFFSET = 20.0
          LEFT_EDGE = 0.0

          attr_reader :arrows, :notes, :fragments, :dividers, :crosses, :left,
                      :right, :y

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

          # @param edge_right [Float, nil] where a message written `->]` ends;
          #   required when the items have one
          def run(items, edge_right: nil)
            @edge_right = edge_right
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
            @crosses = []
            @tracker = BarTracker.new(method(:centre))
            @blocks = []
            @left = Float::INFINITY
            @right = -Float::INFINITY
          end

          def anchoring?(item)
            [Message, Activation, Destroy].any? { |kind| item.is_a?(kind) }
          end

          # A parallel item starts on the row of the one before it, and the
          # page continues below whichever of the two reaches further down.
          def visit(item, previous)
            @resume = nil
            offset = row_offset(item)
            begin_row(item, offset) if offset
            place(item, previous)
            @y = [@y, @resume].max if @resume && !opens_block?(item)
          end

          # How far below its top edge an item's first line sits; nil for an
          # item that does not take a row of its own.
          def row_offset(item)
            case item
            when Message then 0.0
            when Note then TOP_OFFSET
            when Fragment then TOP_OFFSET if item.phase == :open
            end
          end

          def opens_block?(item)
            item.is_a?(Fragment) && item.phase == :open
          end

          # Records the line a following `&` item aligns its top with, or
          # moves a `&` item up to the line the one before it recorded.
          def begin_row(item, offset)
            if item.parallel?
              @resume = @y
              @y = @row_line + offset
            else
              attached = item.is_a?(Note) && item.attached?
              @row_line = attached ? @last_y : @y - offset
            end
          end

          def place(item, previous)
            case item
            when Message then message(item)
            when Activation then activation(item)
            when Destroy then destroy(item)
            when Note then note(item, previous)
            when Fragment then fragment(item)
            else divider(item)
            end
          end

          def message(message)
            @self_drop = message.self_message? ? SELF_HEIGHT : 0.0
            @last_y = @mark_y = @y
            from, to = [message.from, message.to].map do |place|
              place_of(place, message)
            end
            draw(message, from, to) unless message.style.hidden
            touch(*extent(message, from, to))
            @y += message.self_message? ? ROW * 1.5 : ROW
          end

          def draw(message, from, to)
            @arrows << arrow_record(message, arrow_for(message, from, to))
          end

          def extent(message, from, to)
            return [from - reach(message), from] if loops_left?(message)

            low, high = reached(message, from, to).minmax
            [low, high + (message.self_message? ? reach(message) : 0)]
          end

          # The diagram edge belongs to no row's extent: only the participant
          # at the other end does.
          def reached(message, from, to)
            return [from, to] unless message.edge&.global?

            [centre(message.participants.first)]
          end

          # Where an end of a message lands: a lifeline, or an edge, which a
          # ring drawn there pulls inwards.
          def place_of(place, message)
            return centre(place) unless place.is_a?(Edge)

            inward = place.left? ? 1 : -1
            ring = message.edge_end.circle ? Edge::RING_INSET : 0.0
            edge_x(place, message) + (inward * ring)
          end

          def edge_x(edge, message)
            return local_x(edge, message) if edge.local?

            edge.left? ? LEFT_EDGE : @edge_right
          end

          def local_x(edge, message)
            run = @measure.call(message.label.to_s) + Edge::RUN_PADDING
            centre(message.participants.first) + (edge.left? ? -run : run)
          end

          # A bar starts or ends at the arrow it is written on, or else
          # between the rows on either side of the line.
          def activation(item)
            @tracker.apply(item, @mark_y || (@y - 20))
          end

          # The cross sits at the end of the arrow it follows, or else
          # between the rows on either side of the line.
          def destroy(item)
            middle = @mark_y ? @mark_y + @self_drop : @y - 20
            x = centre(item.participant)
            touch(x - CROSS_HALF, x + CROSS_HALF)
            [-CROSS_HALF, CROSS_HALF].each do |slant|
              @crosses << cross_stroke(x, middle, slant)
            end
          end

          def cross_stroke(centre_x, middle, slant)
            PlantUML::Scene::Segment.new(
              x1: centre_x - CROSS_HALF, y1: middle - slant,
              x2: centre_x + CROSS_HALF, y2: middle + slant
            )
          end

          def arrow_for(message, from, to)
            return straight(message, from, to) unless message.self_message?

            self_arrow(message, from)
          end

          def loops_left?(message)
            message.self_message? && message.leftward?
          end

          def centre(id)
            @centers.fetch(@ids.index(id))
          end

          def reach(message)
            SELF_WIDTH + 6 + @measure.call(message.label.to_s)
          end

          def straight(message, from, to)
            sign = to >= from ? 1 : -1
            tail, start = ArrowMarks.for(message.style.tail, from, @y, sign)
            head, stop = ArrowMarks.for(message.style.head, to, @y, -sign)
            { path: "M #{start} #{@y} L #{stop} #{@y}", marks: tail + head,
              label: [(from + to) / 2, @y - 6, "middle"] }
          end

          # The loop leaves and returns on the same side of the lifeline; a
          # message written `<-` loops out on the left.
          def self_arrow(message, centre)
            side = loops_left?(message) ? -1 : 1
            far = centre + (side * SELF_WIDTH)
            bottom = @y + SELF_HEIGHT
            tail, start = ArrowMarks.for(message.style.tail, centre, @y, side)
            head, stop = ArrowMarks.for(message.style.head, centre, bottom,
                                        side)
            { path: "M #{start} #{@y} L #{far} #{@y} L #{far} #{bottom} " \
                    "L #{stop} #{bottom}",
              marks: tail + head, label: loop_label(far, side) }
          end

          def loop_label(far, side)
            [far + (side * 6), @y + 12, side.positive? ? "start" : "end"]
          end

          def arrow_record(message, geometry)
            Scene::Arrow.new(
              id: "message-#{@arrows.size + 1}", path: geometry[:path],
              dashed: message.dashed, marks: geometry[:marks],
              texts: label_texts(message, geometry[:label])
            )
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
                         high: -Float::INFINITY, branches: [], depth: 0,
                         resume: @resume }
            @y += TAB_HEIGHT
          end

          def branch(item)
            @blocks.last[:branches] << [@y - 10, item.label.to_s]
            @y += 28
          end

          def close_block
            block = @blocks.pop
            bottom = @y - 20
            @y = [@y + 10, block[:resume]].compact.max
            @row_line = block[:top]
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
