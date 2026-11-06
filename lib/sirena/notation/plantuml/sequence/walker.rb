# frozen_string_literal: true

require_relative "activation"
require_relative "appearance"
require_relative "message_wrap"
require_relative "tab_size"
require_relative "arrow_marks"
require_relative "bar_tracker"
require_relative "create"
require_relative "destroy"
require_relative "delay"
require_relative "divider"
require_relative "spacing"
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
          LINE_LEADING = NoteGeometry::LINE_LEADING
          SELF_WIDTH = 42.0
          CLASSIC_SELF_WIDTH = 42.0
          CLASSIC_UNLABELLED_SELF_ROW = 27.0
          CLASSIC_ROW_SPARE = 12.3105
          CLASSIC_TAIL = 17.0
          CLASSIC_GUARD_ROW = 13.0
          CLASSIC_SELF_TAIL = 30.0
          CLASSIC_LABEL_INSET = 7.0
          CLASSIC_LABEL_RISE = 4.74
          # A `...` gap is 28 high, and 40.95 with its 11-point text, whose
          # baseline sits 24.63 below the gap's top (PlantUML 1.2026.6).
          CLASSIC_DELAY_ROW = 28.0
          CLASSIC_LABEL_ROW = 21.3105
          CLASSIC_DELAY_LABEL_ROW = 40.9551
          CLASSIC_DELAY_TEXT_DROP = 24.6348
          private_constant :CLASSIC_DELAY_ROW, :CLASSIC_DELAY_LABEL_ROW,
                           :CLASSIC_DELAY_TEXT_DROP
          private_constant :CLASSIC_SELF_WIDTH, :CLASSIC_UNLABELLED_SELF_ROW,
                           :CLASSIC_ROW_SPARE, :CLASSIC_TAIL,
                           :CLASSIC_SELF_TAIL, :CLASSIC_GUARD_ROW,
                           :CLASSIC_LABEL_RISE
          SPARE_ROWS = [Destroy, Spacing, Delay].freeze
          private_constant :SPARE_ROWS
          SELF_HEIGHT = 20.0
          COMPACT_FRAGMENT_SELF_HEIGHT = 17.75
          LOOP_HEIGHT = 13.0
          # PlantUML 1.2026.6 ends the bar of a lifeline one pixel below a
          # loop written on it when the bar closes right after: the loop
          # drops 5, and any bar closing after a loop ends 6 below its row.
          CLOSING_LOOP_DROP = 5.0
          CLOSING_LOOP_BAR_REACH = 6.0
          private_constant :LOOP_HEIGHT, :CLOSING_LOOP_DROP,
                           :CLOSING_LOOP_BAR_REACH
          TAB_HEIGHT = 20.0
          CROSS_HALF = 9.0
          ACTIVATION_END_INSET = 7.0
          TOP_OFFSET = 20.0
          NOTE_ABOVE = 35.0
          # PlantUML 1.2026.6 leaves this much above and below a message row
          # that carries a note.
          ATTACHED_NOTE_PAD = 3.0
          ATTACHED_NOTE_RISE = 5.6895
          STANDALONE_NOTE_RISE = 16.3105
          STANDALONE_NOTE_TAIL = 26.6211
          private_constant :ATTACHED_NOTE_PAD, :ATTACHED_NOTE_RISE,
                           :STANDALONE_NOTE_RISE, :STANDALONE_NOTE_TAIL
          LEFT_EDGE = 0.0
          TEOZ_NESTED_HEADER_ROW = 31.3105
          # What the row of a message that creates a participant gains over
          # a plain one, measured against PlantUML 1.2026.6.
          CREATION_EXTRA_ROW = 12.18
          TEOZ_MESSAGE_HEADER_ROW = 28.6211
          TEOZ_EMPTY_HEADER_ROW = 13.3105
          TEOZ_MESSAGE_BASE_ROW = 14.0
          TEOZ_FRAME_BOTTOM_PAD = 6.0
          TEOZ_ROOT_CLOSE_GAP = 16.6895
          TEOZ_NESTED_CLOSE_GAP = 14.0
          TEOZ_LABEL_HEIGHT = 15.3105
          TEOZ_SELF_CONTACT_INSET = 2.5
          TEOZ_CONTACT_PADDING = 2.0
          private_constant :CREATION_EXTRA_ROW, :TEOZ_NESTED_HEADER_ROW,
                           :TEOZ_MESSAGE_HEADER_ROW,
                           :TEOZ_EMPTY_HEADER_ROW, :TEOZ_MESSAGE_BASE_ROW,
                           :TEOZ_FRAME_BOTTOM_PAD,
                           :TEOZ_ROOT_CLOSE_GAP,
                           :TEOZ_NESTED_CLOSE_GAP, :TEOZ_LABEL_HEIGHT,
                           :TEOZ_SELF_CONTACT_INSET, :TEOZ_CONTACT_PADDING
          PLACERS = { Message => :message, Activation => :activation,
                      Destroy => :destroy, Create => :create,
                      Fragment => :fragment,
                      Ref => :ref, PageBreak => :page_break,
                      Delay => :delay, Spacing => :spacing }.freeze
          Config = Struct.new(:message_measure, :message_font_size,
                              :message_family, :label_inset, :row, :self_row,
                              :unlabelled_row, :following_unlabelled_row,
                              :fragment_row, :branch_gap,
                              :fragment_close_gap, :divider_row,
                              :group_fragment_row, :group_close_gap,
                              :activation_edges, :teoz_fragment_cadence,
                              :note_font_size,
                              :deactivation_gap, :bare_deactivation_gap,
                              :frame_top_offset, :frame_bottom_offset,
                              :branch_offset, :bounds, :head_halves,
                              keyword_init: true)

          def self.following_activations(items, parallel_notes: false)
            items.take_while do |item|
              item.is_a?(Activation) ||
                (parallel_notes && item.is_a?(Note) && item.parallel?)
            end.grep(Activation)
          end

          attr_reader :arrows, :notes, :fragments, :dividers, :delays, :crosses,
                      :left, :right, :y, :page_breaks, :created

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
            @creations = Create.messages(items)
            @fragment_contacts = fragment_contacts(items)
            walk_items(items)
            @tracker.finish(@y - 20)
            @y -= classic_tail_trim(items)
            self
          end

          def bars
            @tracker.bars
          end

          private

          # The foot heads of a plain classic diagram sit CLASSIC_TAIL below
          # the last message line (a self loop's top, CLASSIC_SELF_TAIL), not
          # a whole row below it.
          def classic_tail_trim(items)
            return 0.0 if @label_inset || @teoz_fragment_cadence

            last = items.reverse_each.find { |item| !item.is_a?(Activation) }
            return 0.0 if last.nil? || bar_after?(items, last)

            tail_trim(last)
          end

          def tail_trim(last)
            return CLASSIC_ROW_SPARE if last.is_a?(Fragment)
            return @spare_row if last.is_a?(Message)

            SPARE_ROWS.include?(last.class) ? CLASSIC_ROW_SPARE : 0.0
          end

          # A bar opened and closed after the last message is not drawn the
          # way PlantUML does, so its tail is left as it was.
          def bar_after?(items, last)
            trailing = items.drop(items.rindex { |item| item.equal?(last) } + 1)
            trailing.any?(&:on?) && trailing.any? { |item| !item.on? }
          end

          def apply_config(config)
            apply_message_config(config)
            apply_cadence_config(config)
            @bounds = config.bounds
            @note_font_size = config_value(config, :note_font_size, @font_size)
            @head_halves = config.head_halves || {}
          end

          def apply_message_config(config)
            @message_measure = config_value(config, :message_measure, @measure)
            @monospace_measure = @message_measure
            @message_font_size = config_value(config, :message_font_size,
                                              @font_size)
            @message_family = config.message_family
            @label_inset = config.label_inset
            @teoz_fragment_cadence = config.teoz_fragment_cadence
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
            apply_frame_offsets(config)
          end

          # How far above the row line a frame's top, bottom and `else`
          # line sit.
          def apply_frame_offsets(config)
            @frame_top_offset = config_value(config, :frame_top_offset,
                                             TOP_OFFSET)
            @frame_bottom_offset = config_value(config, :frame_bottom_offset,
                                                TOP_OFFSET)
            @branch_offset = config_value(config, :branch_offset, 10.0)
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
            collect_following_activations(following, item)
            @next_non_activation = following.find do |candidate|
              !candidate.is_a?(Activation)
            end
            @mark_y = nil unless anchoring?(item)
            @headroom = headroom(items, index)
            @item_index = index
          end

          def collect_following_activations(following, item)
            parallel_notes = @label_inset && item.is_a?(Message)
            @following_activations = self.class.following_activations(
              following, parallel_notes: parallel_notes
            )
          end

          def start_empty
            start_collections
            @headroom = 0.0
            @spare_row = 0.0
            @tracker = BarTracker.new(method(:centre))
            @blocks = []
            @left = Float::INFINITY
            @right = -Float::INFINITY
            @created = {}
          end

          def start_collections
            @arrows = []
            @notes = []
            @fragments = []
            @dividers = []
            @delays = []
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
            begin_row(item, offset, previous) if offset
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
            when Note then STANDALONE_NOTE_RISE
            when Ref then TOP_OFFSET
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
          def begin_row(item, offset, previous)
            if item.parallel?
              @resume = @y
              @y = @row_line + offset + parallel_contact_offset(item, previous)
            else
              attached = item.is_a?(Note) && item.attached?
              @row_line = attached ? @last_y : @y - offset
            end
          end

          # Parallel tiles share their contact point, rather than their top.
          # A frame contacts at its top; a self arrow contacts below its shaft.
          def parallel_contact_offset(item, previous)
            return 0.0 unless @teoz_fragment_cadence
            if self_before_frame?(item, previous)
              return TEOZ_SELF_CONTACT_INSET
            end
            return 0.0 unless self_after_frame?(item, previous)

            -TEOZ_SELF_CONTACT_INSET - (self_top - @y)
          end

          def self_before_frame?(item, previous)
            item.is_a?(Fragment) && previous.is_a?(Message) &&
              previous.self_message?
          end

          def self_after_frame?(item, previous)
            item.is_a?(Message) && item.self_message? &&
              previous.is_a?(Fragment) && previous.phase == :close
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
            apply_message_font(message)
            start_row(message)
            @message_activations = active_participants
            from, to = ends_of(message)
            to = created_end(message, from, to)
            draw(message, from, to) unless message.style.hidden
            touch(*extent(message, from, to))
            advance_by(message, message_row(message) + creation_extra(message))
          end

          def advance_by(message, row)
            @spare_row = row - tail_of(message)
            @y += row - @loop_drop
          end

          def closing_loop_drop(message)
            return 0.0 unless classic? && message.self_message?

            closes = @following_activations.any? do |activation|
              !activation.on? && activation.participant == message.from
            end
            closes ? CLOSING_LOOP_DROP : 0.0
          end

          def classic?
            !@label_inset && !@teoz_fragment_cadence
          end

          def tail_of(message)
            message.self_message? ? CLASSIC_SELF_TAIL : CLASSIC_TAIL
          end

          # `create X` has no row of its own; the message to X lands on the
          # left or right edge of X's head, which is drawn at this row.
          def created_end(message, from, to)
            id = @creations[message] or return to

            @created[id] = @y
            to - ((to <=> from) * @head_halves.fetch(id, 0.0))
          end

          def creation_extra(message)
            @creations.key?(message) ? CREATION_EXTRA_ROW : 0.0
          end

          def create(_item)
            nil
          end

          def apply_message_font(message)
            return unless @label_inset

            @message_family = message.label_family || "sans-serif"
            @message_measure = if @message_family == "monospace"
                                 @monospace_measure
                               else
                                 method(:sans_message_width)
                               end
          end

          def sans_message_width(text)
            Drawing::Face.widest_line(text, size: @message_font_size)
          end

          def message_row(message)
            return teoz_message_row(message) if @teoz_fragment_cadence

            return self_message_row(message) if message.self_message?

            plain_message_row(message)
          end

          def plain_message_row(message)
            if following_unlabelled_row?
              return @following_unlabelled_row
            end
            if @unlabelled_row && message.label.to_s.empty?
              return @unlabelled_row
            end

            if @label_inset && message.label_family != "monospace"
              return 29.3105
            end

            @row
          end

          def teoz_message_row(message)
            text_height = teoz_row_text_height(message)
            loop_height = message.self_message? ? LOOP_HEIGHT : 0.0
            TEOZ_MESSAGE_BASE_ROW + text_height + loop_height
          end

          def teoz_row_text_height(message)
            following = @next_non_activation
            if following.is_a?(Message) && !following.parallel?
              return following.label.to_s.empty? ? 0.0 : TEOZ_LABEL_HEIGHT
            end

            teoz_text_height(message)
          end

          def teoz_text_height(message)
            label_lines(message).size * TEOZ_LABEL_HEIGHT
          end

          # A classic loop leaves room for the label of the message that
          # follows it, so the row is short only before an unlabelled one.
          def self_message_row(message)
            return @self_row if @label_inset

            following = @next_non_activation
            labelled = if following.is_a?(Message)
                         !following.label.to_s.empty?
                       else
                         !message.label.to_s.empty?
                       end
            labelled ? @self_row : CLASSIC_UNLABELLED_SELF_ROW
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

          # A note hanging off a message reaches above it; a tall one pushes
          # the message down instead of out over the heads.
          def headroom(items, index)
            return 0.0 unless items[index].is_a?(Message)

            following = items.drop(index + 1).find do |other|
              !other.is_a?(Activation)
            end
            return 0.0 unless following.is_a?(Note) && following.attached?

            attached_note_pad(items[index], following) +
              attached_note_headroom(following)
          end

          # Self arrows, parallel rows and picture notes carry their own
          # spacing.
          def attached_note_pad(item, note)
            return 0.0 if @teoz_fragment_cadence || note.picture
            return 0.0 if item.is_a?(Message) && own_spacing?(item)

            ATTACHED_NOTE_PAD
          end

          def own_spacing?(message)
            message.self_message? || message.parallel?
          end

          def attached_note_headroom(note)
            height = NoteGeometry.height(note)
            clearance = note.picture ? height / 2 : height
            [clearance - NOTE_ABOVE, 0.0].max
          end

          def start_row(message)
            @y += @headroom
            @y += [label_lines(message).size - 1, 0].max * line_step
            @self_drop = message.self_message? ? self_height : 0.0
            @last_y = @mark_y = @y
            @y += @loop_drop = closing_loop_drop(message)
            record_text_height(message)
          end

          def record_text_height(message)
            return if !@teoz_fragment_cadence || @blocks.empty?

            @blocks.last[:text_height] = teoz_text_height(message)
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
            if @label_inset && message.self_message?
              return compact_self_place(place, message, at)
            end
            if @label_inset || @activation_edges
              return compact_activation_place(place, message, at)
            end
            return at unless activated_end?(place, message)

            at + activation_end_inset(place, message, at)
          end

          def compact_self_place(place, message, at)
            depth = compact_activation_depth(place)
            return at if depth.zero?

            side = message.leftward? ? -1 : 1
            at + ((depth - 1 + side) * (BarTracker::WIDTH / 2))
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

            return @edge_right unless edge.left?

            @label_inset ? 10.0 : LEFT_EDGE
          end

          def local_x(edge, message)
            run = label_width(message) + Edge::RUN_PADDING
            centre(message.participants.first) + (edge.left? ? -run : run)
          end

          # A bar starts or ends at the arrow it is written on, or else
          # between the rows on either side of the line.
          def activation(item)
            @tracker.apply(item, bar_edge(item))
            return if item.on? || !@next_non_activation.is_a?(Divider)

            @y += @mark_y ? @deactivation_gap : @bare_deactivation_gap
          end

          def bar_edge(item)
            return @y - 20 unless @mark_y

            loop_closing = !item.on? && classic? && @self_drop.positive?
            loop_closing ? @mark_y + CLOSING_LOOP_BAR_REACH : @mark_y
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
            return self_width + 6 + label_width(message) if @label_inset

            [self_width, CLASSIC_LABEL_INSET + label_width(message)].max
          end

          def label_width(message)
            NumberedLabel.new(@message_measure).extra(message) +
              wrap.width(message.label.to_s)
          end

          def straight(message, from, to)
            sign = to >= from ? 1 : -1
            to -= sign * 2.0 if compact_filled_head?(message)
            tail, start = ArrowMarks.for(message.style.tail, from, @y, sign)
            head, stop = ArrowMarks.for(message.style.head, to, @y, -sign)
            { path: "M #{start} #{@y} L #{stop} #{@y}", marks: tail + head,
              label: straight_label(from, to) }
          end

          def compact_filled_head?(message)
            @label_inset && message.style.head.glyph == :filled &&
              !message.style.head.circle
          end

          def straight_label(from, to)
            return [(from + to) / 2, @y - 6, "middle"] unless @label_inset

            [[from, to].min + @label_inset, @y - 5.0659, "start"]
          end

          # The loop leaves and returns on the same side of the lifeline; a
          # message written `<-` loops out on the left.
          def self_arrow(message, centre)
            side = loops_left?(message) ? -1 : 1
            far = centre + (side * self_reach(message))
            top = self_top
            bottom = top + self_height
            marks, start, stop = self_marks(message, centre, top, bottom, side)
            { path: "M #{start} #{top} L #{far} #{top} L #{far} #{bottom} " \
                    "L #{stop} #{bottom}",
              marks: marks, label: loop_label(far, side) }
          end

          def self_width
            CLASSIC_SELF_WIDTH
          end

          def self_reach(message)
            return self_width unless @label_inset && message.leftward?

            spread = [compact_activation_depth(message.from) - 1, 0].max
            self_width + (spread * (BarTracker::WIDTH / 2))
          end

          def self_marks(message, centre, top, bottom, side)
            tail, start = ArrowMarks.for(message.style.tail, centre, top, side)
            head, stop = ArrowMarks.for(message.style.head, centre, bottom,
                                        side)
            [tail + head, start, stop]
          end

          # The label rides above the loop, inset from the lifeline, on the
          # side the loop leaves by.
          def loop_label(far, side)
            centre = far - (side * SELF_WIDTH)
            rise = @label_inset ? 5.0659 : CLASSIC_LABEL_RISE
            [centre + (side * (@label_inset || CLASSIC_LABEL_INSET)),
             @y - rise, side.positive? ? "start" : "end"]
          end

          def self_height
            LOOP_HEIGHT
          end

          def self_top
            return @y if @teoz_fragment_cadence

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
            height = NoteGeometry.height(note)
            top = note_top(note, on_block, height)
            @notes << note_record(note, [x, top, width, height])
            touch(x, x + width)
            pad = trailing_pad(note, previous, on_block)
            clear_note(note, top + height, pad)
          end

          def clear_note(note, bottom, pad)
            @y = [@y, bottom + note_tail(note)].max + pad
          end

          def trailing_pad(note, previous, on_block)
            return 0.0 if on_block || !note.attached?

            attached_note_pad(previous, note)
          end

          def note_tail(note)
            note.parallel? || note.attached? ? 22 : STANDALONE_NOTE_TAIL
          end

          def note_top(note, on_block, height)
            return @closed[:top] + 5 if on_block
            if note.attached? && note.picture
              return @last_y - (height / 2) + 10
            end

            return @last_y - height + ATTACHED_NOTE_RISE if note.attached?

            @y - STANDALONE_NOTE_RISE
          end

          def block_box(note)
            natural = NoteGeometry.natural_width(note, @note_font_size)
            NoteGeometry.beside(@closed[:shape], natural)
          end

          def note_box(note, previous)
            span = NoteGeometry.span(note, previous, @ids)
            natural = NoteGeometry.natural_width(note, @note_font_size)
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

            step = NoteGeometry.line_height(@note_font_size)
            note.lines.each_with_index.map do |line, index|
              baseline = top + NoteGeometry::FIRST_BASELINE + (index * step)
              text(line, left, baseline, "note", "start")
            end
          end

          # Between the rows on either side of the line, like a divider.
          def page_break(_item)
            @page_breaks << (@y - 20)
          end

          def ref(item)
            shape = ref_shape(item)
            @fragments << shape.scene
            touch(shape.x, shape.x + shape.width)
            @y += RefShape::HEIGHT + RefShape::TAIL
          end

          def ref_shape(item)
            span = item.targets.map { |id| centre(id) }.minmax
            RefShape.new(item, @y - @frame_bottom_offset, span, @measure)
          end

          def fragment(item)
            case item.phase
            when :open then open_block(item)
            when :else then branch(item)
            else close_block
            end
          end

          def open_block(item)
            @y += @fragment_contacts.fetch(@item_index, 0.0)
            @blocks << { keyword: item.keyword, label: item.label.to_s,
                         top: @y - @frame_top_offset, low: Float::INFINITY,
                         high: -Float::INFINITY, branches: [], depth: 0,
                         resume: @resume, tab: tab_size, text_height: 0.0 }
            @y += fragment_row(item) + tab_size.height_growth
          end

          def fragment_row(item)
            return teoz_header_row if @teoz_fragment_cadence

            return @group_fragment_row if group?(item) && @group_fragment_row

            @fragment_row
          end

          def teoz_header_row
            following = @next_non_activation
            if following.is_a?(Fragment) && following.phase == :open
              return TEOZ_NESTED_HEADER_ROW
            end

            if following.is_a?(Message) && !following.label.to_s.empty?
              return TEOZ_MESSAGE_HEADER_ROW
            end

            TEOZ_EMPTY_HEADER_ROW
          end

          def fragment_contacts(items)
            return {} unless @teoz_fragment_cadence

            fragment_ends(items).transform_values do |index|
              message = following_parallel_self(items, index)
              message ? self_contact(message) : 0.0
            end
          end

          def fragment_ends(items)
            stack = []
            items.each_with_index.with_object({}) do |(item, index), ends|
              next unless item.is_a?(Fragment)

              stack << index if item.phase == :open
              ends[stack.pop] = index if item.phase == :close
            end
          end

          def following_parallel_self(items, index)
            following = items.drop(index + 1).find do |item|
              !item.is_a?(Activation)
            end
            return unless following.is_a?(Message) && following.parallel?

            following if following.self_message?
          end

          def self_contact(message)
            text_height = label_lines(message).size * TEOZ_LABEL_HEIGHT
            text_height + (LOOP_HEIGHT / 2) + TEOZ_CONTACT_PADDING
          end

          def group?(fragment)
            fragment.keyword == "group"
          end

          def tab_size
            TabSize.new(@appearance.tab_size, @font_size)
          end

          def branch(item)
            @blocks.last[:branches] << [@y - @branch_offset, item.label.to_s]
            @y += branch_row + classic_guard_row(item)
          end

          def classic_guard_row(item)
            return 0.0 if @label_inset || item.label.to_s.strip.empty?

            CLASSIC_GUARD_ROW
          end

          def branch_row
            return @branch_gap unless @teoz_fragment_cadence

            following = @next_non_activation
            if following.is_a?(Message) && following.label.to_s.empty?
              return @branch_gap - TEOZ_LABEL_HEIGHT
            end

            @branch_gap
          end

          def close_block
            block = @blocks.pop
            bottom = @y - fragment_bottom_offset(block)
            @y = [@y + close_gap(block), block[:resume]].compact.max
            @row_line = block[:top]
            emit_fragment(block, bottom)
          end

          def fragment_bottom_offset(block)
            return @frame_bottom_offset unless @teoz_fragment_cadence

            block[:text_height] + TEOZ_FRAME_BOTTOM_PAD
          end

          def close_gap(block)
            if @teoz_fragment_cadence
              return teoz_root_close_gap(block) if @blocks.empty?

              return TEOZ_NESTED_CLOSE_GAP
            end
            return @group_close_gap if group_close_gap?(block)

            @fragment_close_gap
          end

          def teoz_root_close_gap(block)
            following = @next_non_activation
            return TEOZ_ROOT_CLOSE_GAP unless following.is_a?(Message)
            return TEOZ_ROOT_CLOSE_GAP if following.parallel?

            next_text = following.label.to_s.empty? ? 0.0 : TEOZ_LABEL_HEIGHT
            TEOZ_NESTED_CLOSE_GAP + next_text - block[:text_height]
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
            return unless parent

            parent[:depth] = [parent[:depth], block[:depth] + 1].max
            parent[:text_height] = block[:text_height]
          end

          def spacing(item)
            @y += item.room
          end

          # The lifelines run on through the gap, dotted over it in a classic
          # diagram.
          def delay(item)
            label = item.label.to_s
            return plain_delay(label) if @label_inset || @teoz_fragment_cadence

            gap = label.empty? ? CLASSIC_DELAY_ROW : CLASSIC_DELAY_LABEL_ROW
            top = @y - CLASSIC_LABEL_ROW
            @delays << delay_record(label, top, top + gap,
                                    CLASSIC_DELAY_TEXT_DROP)
            @y = top + gap + delay_clearance
          end

          # What the next message's row needs below the gap.
          def delay_clearance
            following_unlabelled_message? ? 6.0 : CLASSIC_LABEL_ROW
          end

          def plain_delay(label)
            @delays << delay_record(label, @y, @y, 5) unless label.empty?
            @y += @divider_row
          end

          def delay_record(label, top, bottom, drop)
            texts = label.empty? ? [] : [delay_text(label, top + drop)]
            Scene::Delay.new(y1: top, y2: bottom, texts: texts)
          end

          def delay_text(label, at_y)
            middle = (@bounds[0] + @bounds[1]) / 2
            half = @measure.call(label) / 2
            touch(middle - half, middle + half)
            text(label, middle, at_y, "delay")
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
