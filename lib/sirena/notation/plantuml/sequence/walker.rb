# frozen_string_literal: true

require_relative "activation"
require_relative "appearance"
require_relative "message_wrap"
require_relative "tab_size"
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
require_relative "numbered_label"
require_relative "page_break"
require_relative "note_shape"
require_relative "ref"
require_relative "ref_shape"
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
          LINE_LEADING = 1.1776
          SELF_WIDTH = 36.0
          CLASSIC_SELF_WIDTH = 42.0
          CLASSIC_UNLABELLED_SELF_ROW = 27.0
          private_constant :CLASSIC_SELF_WIDTH, :CLASSIC_UNLABELLED_SELF_ROW
          SELF_HEIGHT = 20.0
          COMPACT_FRAGMENT_SELF_HEIGHT = 17.75
          LOOP_HEIGHT = 13.0
          private_constant :LOOP_HEIGHT
          TAB_HEIGHT = 20.0
          CROSS_HALF = 9.0
          ACTIVATION_END_INSET = 7.0
          TOP_OFFSET = 20.0
          NOTE_ABOVE = 35.0
          LEFT_EDGE = 0.0
          PLACERS = { Message => :message, Activation => :activation,
                      Destroy => :destroy, Fragment => :fragment,
                      Ref => :ref, PageBreak => :page_break }.freeze
          Config = Struct.new(:message_measure, :message_font_size,
                              :message_family, :label_inset, :row, :self_row,
                              :unlabelled_row, :following_unlabelled_row,
                              :fragment_row, :branch_gap,
                              :fragment_close_gap, :divider_row,
                              :group_fragment_row, :group_close_gap,
                              :activation_edges,
                              :deactivation_gap, :bare_deactivation_gap,
                              :bounds,
                              keyword_init: true)

          attr_reader :arrows, :notes, :fragments, :dividers, :crosses, :left,
                      :right, :y, :page_breaks

          # @param lifelines [Hash{String => Float}] centre of each
          #   participant's lifeline, in participant order
          # @param measure [#call] text width in pixels
          # @param start_y [Float] where the first row goes
          # @param config [Config] `bounds` is the left and right edge of the
          #   heads
          def initialize(lifelines:, measure:, font_size:, start_y:,
                         config: Config.new)
            @ids = lifelines.keys
            @centers = lifelines.values
            @measure = measure
            @font_size = font_size
            @y = start_y
            apply_config(config)
            start_empty
          end

          # @param edge_right [Float, nil] where a message written `->]` ends;
          #   required when the items have one
          # @param appearance [Appearance] what the fragment tabs are drawn in
          def run(items, edge_right: nil, appearance: Appearance.new)
            @edge_right = edge_right
            @appearance = appearance
            @fragmented = items.any?(Fragment)
            walk_items(items)
            @tracker.finish(@y - 20)
            self
          end

          def bars
            @tracker.bars
          end

          private

          def apply_config(config)
            apply_message_config(config)
            apply_cadence_config(config)
            @bounds = config.bounds
          end

          def apply_message_config(config)
            @message_measure = config_value(config, :message_measure, @measure)
            @message_font_size = config_value(config, :message_font_size,
                                              @font_size)
            @message_family = config.message_family
            @label_inset = config.label_inset
            @activation_edges = config.activation_edges
          end

          def apply_cadence_config(config)
            @row = config_value(config, :row, ROW)
            @self_row = config_value(config, :self_row, ROW * 1.5)
            apply_fragment_cadence(config)
            @divider_row = config_value(config, :divider_row, ROW)
            @deactivation_gap = config_value(config, :deactivation_gap, 0.0)
            @bare_deactivation_gap = config_value(
              config, :bare_deactivation_gap, 0.0
            )
          end

          def apply_fragment_cadence(config)
            @unlabelled_row = config.unlabelled_row
            @following_unlabelled_row = config.following_unlabelled_row
            @fragment_row = config_value(config, :fragment_row, TAB_HEIGHT)
            @branch_gap = config_value(config, :branch_gap, 28.0)
            @fragment_close_gap = config_value(config, :fragment_close_gap,
                                               10.0)
            @group_fragment_row = config.group_fragment_row
            @group_close_gap = config.group_close_gap
          end

          def config_value(config, member, default)
            config[member] || default
          end

          def walk_items(items)
            previous = nil
            items.each_with_index do |item, index|
              prepare_item(items, index, item)
              visit(item, previous)
              previous = item unless item.is_a?(Activation)
            end
          end

          def prepare_item(items, index, item)
            following = items.drop(index + 1)
            @following_activations = following.take_while do |candidate|
              candidate.is_a?(Activation)
            end
            @next_non_activation = following.find do |candidate|
              !candidate.is_a?(Activation)
            end
            @mark_y = nil unless anchoring?(item)
            @headroom = headroom(items, index)
          end

          def start_empty
            start_collections
            @headroom = 0.0
            @tracker = BarTracker.new(method(:centre))
            @blocks = []
            @left = Float::INFINITY
            @right = -Float::INFINITY
          end

          def start_collections
            @arrows = []
            @notes = []
            @fragments = []
            @dividers = []
            @crosses = []
            @page_breaks = []
          end

          def anchoring?(item)
            [Message, Activation, Destroy].any? { |kind| item.is_a?(kind) }
          end

          # A parallel item starts on the row of the one before it, and the
          # page continues below whichever of the two reaches further down.
          def visit(item, previous)
            @previous_self_message = false unless continues_self_run?(item)
            @resume = nil
            offset = row_offset(item)
            begin_row(item, offset) if offset
            place(item, previous)
            resume_after_parallel(item) if @resume && !opens_block?(item)
          end

          def resume_after_parallel(item)
            @y = if parallel_side_note?(item)
                   @resume
                 else
                   [@y, @resume].max
                 end
          end

          def parallel_side_note?(item)
            item.is_a?(Note) && !item.targets.empty? &&
              %i[left right].include?(item.side)
          end

          # How far below its top edge an item's first line sits; nil for an
          # item that does not take a row of its own.
          def row_offset(item)
            case item
            when Message then 0.0
            when Note, Ref then TOP_OFFSET
            when Fragment then TOP_OFFSET if item.phase == :open
            end
          end

          def continues_self_run?(item)
            item.is_a?(Message) || item.is_a?(Activation)
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
            return note(item, previous) if item.is_a?(Note)

            handler = PLACERS.find { |type, _| item.is_a?(type) }
            send(handler ? handler.last : :divider, item)
          end

          def wrap
            MessageWrap.new(@appearance.max_message, @message_measure)
          end

          def message(message)
            adjust_self_run(message)
            start_row(message)
            @message_activations = active_participants
            from, to = ends_of(message)
            draw(message, from, to) unless message.style.hidden
            touch(*extent(message, from, to))
            @y += message_row(message)
            @previous_self_message = message.self_message? && !message.parallel?
          end

          def message_row(message)
            return self_message_row(message) if message.self_message?
            if following_unlabelled_row?
              return @following_unlabelled_row
            end
            if @unlabelled_row && message.label.to_s.empty?
              return @unlabelled_row
            end

            @row
          end

          def self_message_row(message)
            return @self_row if @label_inset || !message.label.to_s.empty?

            CLASSIC_UNLABELLED_SELF_ROW
          end

          def following_unlabelled_row?
            @following_unlabelled_row && following_unlabelled_message?
          end

          def following_unlabelled_message?
            @next_non_activation.is_a?(Message) &&
              (!@label_inset || !@next_non_activation.self_message?) &&
              @next_non_activation.label.to_s.empty?
          end

          def active_participants
            @following_activations.select(&:on?).map(&:participant)
          end

          def adjust_self_run(message)
            return unless @label_inset && !message.parallel?

            @y += @self_row - @row if entering_self_run?(message)
            @y -= @self_row - @row if leaving_self_run?(message)
          end

          def entering_self_run?(message)
            message.self_message? && !@previous_self_message
          end

          def leaving_self_run?(message)
            !message.self_message? && @previous_self_message
          end

          # A note hanging off a message reaches above it; a tall one pushes
          # the message down instead of out over the heads.
          def headroom(items, index)
            return 0.0 unless items[index].is_a?(Message)

            following = items.drop(index + 1).find do |other|
              !other.is_a?(Activation)
            end
            return 0.0 unless following.is_a?(Note) && following.attached?

            attached_note_headroom(following)
          end

          def attached_note_headroom(note)
            height = NoteGeometry.height(note, @font_size)
            clearance = note.picture ? height / 2 : height
            [clearance - NOTE_ABOVE, 0.0].max
          end

          def start_row(message)
            @y += @headroom
            @y += [label_lines(message).size - 1, 0].max * line_step
            @self_drop = message.self_message? ? self_height : 0.0
            @last_y = @mark_y = @y
          end

          def ends_of(message)
            [message.from, message.to].map { |place| place_of(place, message) }
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
            return participant_place(place, message) unless place.is_a?(Edge)

            inward = place.left? ? 1 : -1
            ring = message.edge_end.circle ? Edge::RING_INSET : 0.0
            edge_x(place, message) + (inward * ring)
          end

          def participant_place(place, message)
            at = centre(place)
            if @activation_edges
              return compact_activation_place(place, message, at)
            end
            return at unless activated_end?(place, message)

            at + activation_end_inset(place, message, at)
          end

          def compact_activation_place(place, message, at)
            depth = compact_activation_depth(place)
            return at if depth.zero?

            other = place == message.to ? message.from : message.to
            toward = activation_direction(other, at)
            at + ((depth - 1) * (BarTracker::WIDTH / 2)) +
              (toward * (BarTracker::WIDTH / 2))
          end

          def activation_direction(other, at)
            return other.left? ? -1 : 1 if other.is_a?(Edge)

            centre(other) < at ? -1 : 1
          end

          def compact_activation_depth(place)
            opening = @following_activations.count do |activation|
              activation.participant == place && activation.on?
            end
            @tracker.depth(place) + opening
          end

          def activation_end_inset(place, message, at)
            other = place == message.to ? message.from : message.to
            direction = centre(other) < at ? -1 : 1
            direction * ACTIVATION_END_INSET
          end

          def activated_end?(place, message)
            !@label_inset && !message.self_message? &&
              @message_activations.include?(place)
          end

          def edge_x(edge, message)
            return local_x(edge, message) if edge.local?

            edge.left? ? LEFT_EDGE : @edge_right
          end

          def local_x(edge, message)
            run = label_width(message) + Edge::RUN_PADDING
            centre(message.participants.first) + (edge.left? ? -run : run)
          end

          # A bar starts or ends at the arrow it is written on, or else
          # between the rows on either side of the line.
          def activation(item)
            @tracker.apply(item, @mark_y || (@y - 20))
            return if item.on? || !@next_non_activation.is_a?(Divider)

            @y += @mark_y ? @deactivation_gap : @bare_deactivation_gap
          end

          # The cross sits at the end of the arrow it follows, or else
          # between the rows on either side of the line.
          def destroy(item)
            middle = @mark_y ? @mark_y + @self_drop : @y - 20
            x = centre(item.participant)
            @tracker.destroy(item.participant, middle) if @activation_edges
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
            self_width + 6 + label_width(message)
          end

          def label_width(message)
            NumberedLabel.new(@message_measure).extra(message) +
              wrap.width(message.label.to_s)
          end

          def straight(message, from, to)
            sign = to >= from ? 1 : -1
            tail, start = ArrowMarks.for(message.style.tail, from, @y, sign)
            head, stop = ArrowMarks.for(message.style.head, to, @y, -sign)
            { path: "M #{start} #{@y} L #{stop} #{@y}", marks: tail + head,
              label: straight_label(from, to) }
          end

          def straight_label(from, to)
            return [(from + to) / 2, @y - 6, "middle"] unless @label_inset

            [[from, to].min + @label_inset, @y - 5.0659, "start"]
          end

          # The loop leaves and returns on the same side of the lifeline; a
          # message written `<-` loops out on the left.
          def self_arrow(message, centre)
            side = loops_left?(message) ? -1 : 1
            far = centre + (side * self_width)
            top = self_top
            bottom = top + self_height
            marks, start, stop = self_marks(message, centre, top, bottom, side)
            { path: "M #{start} #{top} L #{far} #{top} L #{far} #{bottom} " \
                    "L #{stop} #{bottom}",
              marks: marks, label: loop_label(far, side) }
          end

          def self_width
            @label_inset ? SELF_WIDTH : CLASSIC_SELF_WIDTH
          end

          def self_marks(message, centre, top, bottom, side)
            tail, start = ArrowMarks.for(message.style.tail, centre, top, side)
            head, stop = ArrowMarks.for(message.style.head, centre, bottom,
                                        side)
            [tail + head, start, stop]
          end

          def loop_label(far, side)
            unless @label_inset
              return [far + (side * 6), @y + 12,
                      side.positive? ? "start" : "end"]
            end

            centre = far - (side * SELF_WIDTH)
            [centre + (side * @label_inset), @y - 18.0659,
             side.positive? ? "start" : "end"]
          end

          def self_height
            return LOOP_HEIGHT unless @label_inset
            return COMPACT_FRAGMENT_SELF_HEIGHT if @fragmented

            SELF_HEIGHT
          end

          def self_top
            return @y unless @label_inset && @fragmented

            @y + ((SELF_HEIGHT - self_height) / 2)
          end

          def arrow_record(message, geometry)
            Scene::Arrow.new(
              id: "message-#{@arrows.size + 1}", path: geometry[:path],
              dashed: message.dashed, colour: message.style.colour,
              marks: geometry[:marks],
              texts: label_texts(message, geometry[:label])
            )
          end

          def label_texts(message, geometry)
            return [] unless message.label && !message.label.empty?
            return numbered_texts(message, geometry) if message.number

            stacked_texts(message, *geometry)
          end

          def numbered_texts(message, geometry)
            NumberedLabel.new(@message_measure,
                              size: compact_message_size,
                              family: @message_family)
              .texts(message, *geometry)
          end

          def compact_message_size
            @message_font_size if @message_family
          end

          def stacked_texts(message, at_x, at_y, anchor)
            lines = label_lines(message)
            lines.each_with_index.map do |line, index|
              up = (lines.size - 1 - index) * line_step
              text(line, at_x, at_y - up, "message_label", anchor)
            end
          end

          def label_lines(message)
            return [] if message.label.to_s.empty?

            wrap.lines(message.label)
          end

          # PlantUML stacks wrapped lines 1.1776 of the text size apart.
          def line_step
            @message_font_size * LINE_LEADING
          end

          def text(content, at_x, at_y, role, anchor = "middle")
            message = role == "message_label"
            PlantUML::Scene::Text.new(
              content: content, x: at_x, y: at_y, role: role, anchor: anchor,
              size: (@message_font_size if message && @message_family),
              family: (@message_family if message)
            )
          end

          def touch(low, high)
            @left = [@left, low].min
            @right = [@right, high].max
            return if @blocks.empty?

            @blocks.last[:low] = [@blocks.last[:low], low].min
            @blocks.last[:high] = [@blocks.last[:high], high].max
          end

          def note(note, previous)
            on_block = note.attached? && previous.is_a?(Fragment)
            x, width = on_block ? block_box(note) : note_box(note, previous)
            height = NoteGeometry.height(note, @font_size)
            top = note_top(note, on_block, height)
            @notes << note_record(note, [x, top, width, height])
            touch(x, x + width)
            @y = [@y, top + height + 22].max
          end

          def note_top(note, on_block, height)
            return @closed[:top] + 5 if on_block
            if note.attached? && note.picture
              return @last_y - (height / 2) + 10
            end

            note.attached? ? @last_y - height + 10 : @y - 20
          end

          def block_box(note)
            natural = NoteGeometry.natural_width(note, @measure)
            NoteGeometry.beside(@closed[:shape], natural)
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
              fill: note.fill&.colour, fill_opacity: note.fill&.opacity,
              texts: note_texts(note, x + NoteGeometry::PAD, top),
              picture: note_picture(note, x + NoteGeometry::PAD, top + 7)
            )
          end

          def note_picture(note, left, top)
            return unless note.picture

            inset = NoteGeometry.picture_inset(note.picture)
            Scene::Picture.new(x: left - inset, y: top - inset,
                               scale: note.picture.scale,
                               scene: note.picture.scene)
          end

          def note_texts(note, left, top)
            return [] if note.picture

            step = NoteGeometry.line_height(@font_size)
            note.lines.each_with_index.map do |line, index|
              baseline = top + 7 + (index * step) + @font_size
              text(line, left, baseline, "note", "start")
            end
          end

          # Between the rows on either side of the line, like a divider.
          def page_break(_item)
            @page_breaks << (@y - 20)
          end

          def ref(item)
            span = item.targets.map { |id| centre(id) }.minmax
            shape = RefShape.new(item, @y - 20, span, @measure)
            @fragments << shape.scene
            touch(shape.x, shape.x + shape.width)
            @y += RefShape::HEIGHT + 10
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
                         resume: @resume, tab: tab_size }
            @y += fragment_row(item) + tab_size.height_growth
          end

          def fragment_row(item)
            return @group_fragment_row if group?(item) && @group_fragment_row

            @fragment_row
          end

          def group?(fragment)
            fragment.keyword == "group"
          end

          def tab_size
            TabSize.new(@appearance.tab_size, @font_size)
          end

          def branch(item)
            @blocks.last[:branches] << [@y - 10, item.label.to_s]
            @y += @branch_gap
          end

          def close_block
            block = @blocks.pop
            bottom = @y - 20
            @y = [@y + close_gap(block), block[:resume]].compact.max
            @row_line = block[:top]
            emit_fragment(block, bottom)
          end

          def close_gap(block)
            return @group_close_gap if group_close_gap?(block)

            @fragment_close_gap
          end

          def group_close_gap?(block)
            block[:keyword] == "group" && @group_close_gap
          end

          def emit_fragment(block, bottom)
            record = FragmentShape.new(block, bottom, @centers, @measure,
                                       @appearance)
            @fragments << record.scene
            @closed = { shape: record, top: block[:top] }
            touch(record.x, record.x + record.width)
            deepen_parent(block)
          end

          def deepen_parent(block)
            parent = @blocks.last
            parent[:depth] = [parent[:depth], block[:depth] + 1].max if parent
          end

          def divider(item)
            left, right = @bounds
            label = item.label.to_s
            @dividers << divider_record(label, left, right)
            @y += @divider_row
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
