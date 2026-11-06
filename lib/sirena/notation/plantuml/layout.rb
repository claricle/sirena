# frozen_string_literal: true

require_relative "../../layout/base"
require_relative "caption_layout"
require_relative "class_name"
require_relative "stereotype_head"
require_relative "class_header"
require_relative "end_texts"
require_relative "member_icon"
require_relative "member_pitch"
require_relative "member_rule"
require_relative "ir_reader"
require_relative "package_frames"
require_relative "qualified_association_layout"
require_relative "qualifier_box"
require_relative "label_clearance"
require_relative "styled_relation_curve"
require_relative "rank_chain"
require_relative "rank_hierarchy"
require_relative "note_layout"
require_relative "relation_label_separator"
require_relative "scene"
require_relative "drawing"
require_relative "../../js_math"

module Sirena
  module Notation
    module PlantUML
      # Positions PlantUML class boxes and relations in final canvas space,
      # from the IR::Graph {IRAdapter} emits.
      class Layout < Sirena::Layout::Base
        MARGIN = 36.0
        COLUMN_GAP = 90.0
        ROW_GAP = 90.0
        ANNOTATED_RELATION_SLOT_WIDTH = 160.0
        BOX_PADDING = 12.0
        ROW_HEIGHT = 22.0
        # A compact box, sized from the reference row pitch, draws its member
        # rows from the bottom edge: last baseline 6.95 above it, the head
        # rule 17.5 above the first baseline, 8.0 between a field group and
        # a method group.
        COMPACT_BOTTOM_PAD = 6.95
        COMPACT_HEAD_GAP = 17.5
        COMPACT_GROUP_GAP = 8.0
        # The head rule is 32 below the top and the first row 17.5 below it,
        # the last row 6.95 above the bottom, less the pitch of that row.
        PROPORTIONAL_MEMBER_BASE_HEIGHT = 40.0
        COMPACT_RULE_BASE_HEIGHT = 34.488
        MARKER_LENGTH = 12.0
        THICK_LINE = 4.0
        JUNCTION_DOT_RADIUS = 2.0
        MARKER_HALF_WIDTH = 7.0
        LABEL_OFFSET = 10.0
        LABEL_GAP = 2.0
        BESIDE_LABEL_SLOPE = 0.8
        END_TEXT_ACROSS = 3.0
        END_TEXT_ALONG = 1.0
        TEXT_DESCENT = 0.25
        # The renderer draws end texts and relation labels at this share of
        # the body font size.
        SMALL_TEXT_SCALE = 0.9
        NESTING_RADIUS = 8.0
        MEMBER_NOTE_TEXT_SCALE = 1.15
        MEMBER_NOTE_ROW_HEIGHT = 16.48828125
        MEMBER_NOTE_LINE_HEIGHT = 15.310546875
        MEMBER_NOTE_STACK_GAP = 10.0
        MEMBER_NOTE_BODY_GAP = 35.0
        CLASS_NOTE_GAP = 35.0
        MEMBER_NOTE_CLASS_HEIGHT = 48.0
        MEMBER_NOTE_SIDE_PADDING = 6.0
        STANDARD_MEMBER_SIDE_ALLOWANCE = 20.0
        STANDARD_STEREOTYPE_ROW_HEIGHT = 8.62109375
        STANDARD_TITLE_SIDE_ALLOWANCE = 32.0
        MULTILINE_TITLE_ROW_HEIGHT = 16.48828125
        MULTILINE_TITLE_VERTICAL_ALLOWANCE = 26.0
        MULTILINE_TITLE_BASELINE = 18.53515625
        MULTILINE_TITLE_SIDE_ALLOWANCE = 36.0
        SELF_RELATION_START_RATIO = 0.37
        SELF_RELATION_END_RATIO = 0.635
        SELF_RELATION_CONTROL_OFFSET = 70.0
        SELF_RELATION_LABEL_GAP = 6.0
        # PlantUML removes the otherwise empty member compartment below a
        # one-line title when `hide empty members` is active. Its Smetana
        # boxes also keep four more pixels of side padding than our ordinary
        # measured class box; both values are pinned by the group2712 family.
        EMPTY_MEMBER_COMPARTMENT = 14.0
        EMPTY_COMPARTMENTS_EXTRA = 2.0
        AXIS_TOLERANCE = 0.5
        EMPTY_CLASS_WIDTH_EXTRA = 8.0
        EMPTY_CLASS_MIN_WIDTH = 41.5
        HIDE_CIRCLE_BASE_HEIGHT = 42.48828125
        HIDE_CIRCLE_TITLE_ALLOWANCE = 6.0
        HIDE_CIRCLE_MEMBER_ALLOWANCE = 12.0
        ISOLATED_KIND_COLUMN_GAP = 35.0
        ISOLATED_KIND_ROW_GAP = 60.0
        ISOLATED_KIND_MEMBER_ALLOWANCE = 26.0
        HIDDEN_MEMBER_EMPTY_HEIGHT = 32.0
        RESHOWN_MEMBER_BASE_HEIGHT = 40.0
        QUALIFIED_GENERIC_FONT_SIZE = 12.0
        QUALIFIED_GENERIC_GAP = 7.0
        QUALIFIED_BOX_HEIGHT = 48.0
        QUALIFIED_GENERIC_HEIGHT = 51.0
        QUALIFIED_QUALIFIER_ALLOWANCE = 40.0
        COMPACT_QUALIFIER_ALLOWANCE = 20.0
        QUALIFIED_STEEP_ARROW_OFFSET = 37.0
        QUALIFIED_LONG_CURVE_OFFSET = 210.0
        QUALIFIED_FLAT_CURVE_OFFSET = 30.0
        QUALIFIED_FAN_LANE_ALLOWANCE = 4.0
        QUALIFIED_DOUBLE_END_HALF_WIDTH = 10.0
        QUALIFIED_INHERITANCE_HALF_WIDTH = 6.0
        PACKAGE_CANVAS_MARGIN = 6.0
        PACKAGE_OUTER_GAP = 24.0
        PACKAGE_CANVAS_EDGE = 15.0
        ARROW_LENGTH = 9.0
        ARROW_HALF_WIDTH = 4.0
        ARROW_NOTCH = 5.0
        DIAMOND_LENGTH = 12.0
        DIAMOND_HALF_WIDTH = 4.0
        ARROW_MARKERS = %i[association dependency].freeze
        FILLED_MARKERS = %i[association dependency composition].freeze
        private_constant :PROPORTIONAL_MEMBER_BASE_HEIGHT,
                         :COMPACT_BOTTOM_PAD, :COMPACT_HEAD_GAP,
                         :COMPACT_GROUP_GAP, :COMPACT_RULE_BASE_HEIGHT
        private_constant :MARGIN, :COLUMN_GAP, :ROW_GAP,
                         :ANNOTATED_RELATION_SLOT_WIDTH, :BOX_PADDING,
                         :ROW_HEIGHT, :MARKER_LENGTH, :MARKER_HALF_WIDTH,
                         :LABEL_OFFSET, :LABEL_GAP, :FILLED_MARKERS,
                         :NESTING_RADIUS,
                         :END_TEXT_ACROSS, :END_TEXT_ALONG, :TEXT_DESCENT,
                         :SMALL_TEXT_SCALE,
                         :ARROW_LENGTH, :ARROW_HALF_WIDTH, :ARROW_NOTCH,
                         :DIAMOND_LENGTH, :DIAMOND_HALF_WIDTH,
                         :ARROW_MARKERS,
                         :MEMBER_NOTE_TEXT_SCALE, :MEMBER_NOTE_ROW_HEIGHT,
                         :MEMBER_NOTE_LINE_HEIGHT, :MEMBER_NOTE_STACK_GAP,
                         :MEMBER_NOTE_BODY_GAP, :MEMBER_NOTE_CLASS_HEIGHT,
                         :MEMBER_NOTE_SIDE_PADDING,
                         :CLASS_NOTE_GAP,
                         :STANDARD_MEMBER_SIDE_ALLOWANCE,
                         :STANDARD_STEREOTYPE_ROW_HEIGHT,
                         :STANDARD_TITLE_SIDE_ALLOWANCE,
                         :MULTILINE_TITLE_ROW_HEIGHT,
                         :MULTILINE_TITLE_VERTICAL_ALLOWANCE,
                         :MULTILINE_TITLE_BASELINE,
                         :MULTILINE_TITLE_SIDE_ALLOWANCE,
                         :SELF_RELATION_START_RATIO,
                         :SELF_RELATION_END_RATIO,
                         :SELF_RELATION_CONTROL_OFFSET,
                         :SELF_RELATION_LABEL_GAP,
                         :EMPTY_MEMBER_COMPARTMENT,
                         :EMPTY_COMPARTMENTS_EXTRA, :AXIS_TOLERANCE,
                         :EMPTY_CLASS_WIDTH_EXTRA,
                         :EMPTY_CLASS_MIN_WIDTH, :HIDE_CIRCLE_BASE_HEIGHT,
                         :HIDE_CIRCLE_TITLE_ALLOWANCE,
                         :HIDE_CIRCLE_MEMBER_ALLOWANCE,
                         :ISOLATED_KIND_COLUMN_GAP,
                         :ISOLATED_KIND_ROW_GAP,
                         :ISOLATED_KIND_MEMBER_ALLOWANCE,
                         :HIDDEN_MEMBER_EMPTY_HEIGHT,
                         :RESHOWN_MEMBER_BASE_HEIGHT,
                         :QUALIFIED_GENERIC_FONT_SIZE,
                         :QUALIFIED_GENERIC_GAP, :QUALIFIED_BOX_HEIGHT,
                         :QUALIFIED_GENERIC_HEIGHT,
                         :QUALIFIED_QUALIFIER_ALLOWANCE,
                         :COMPACT_QUALIFIER_ALLOWANCE,
                         :QUALIFIED_STEEP_ARROW_OFFSET,
                         :QUALIFIED_LONG_CURVE_OFFSET,
                         :QUALIFIED_FLAT_CURVE_OFFSET,
                         :QUALIFIED_FAN_LANE_ALLOWANCE,
                         :QUALIFIED_DOUBLE_END_HALF_WIDTH,
                         :QUALIFIED_INHERITANCE_HALF_WIDTH,
                         :PACKAGE_CANVAS_MARGIN, :PACKAGE_OUTER_GAP,
                         :PACKAGE_CANVAS_EDGE

        # @param graph [IR::Graph] from {IRAdapter}
        def scene(graph)
          diagram = IRReader.call(graph)
          @kind_in_spot = !ClassHeader.circles_hidden?(diagram)
          body = if member_note_family?(diagram)
                   member_note_scene(diagram)
                 elsif class_note_pair_family?(diagram)
                   class_note_pair_scene(diagram)
                 else
                   standard_scene(diagram)
                 end
          dress(diagram, body)
        end

        private

        def standard_scene(diagram)
          specifications = box_specifications(diagram)
          hidden_members = hide_members_grid_scene(diagram, specifications)
          return hidden_members if hidden_members

          isolated_kinds = isolated_class_kind_scene(diagram, specifications)
          return isolated_kinds if isolated_kinds

          qualified = qualified_scene(diagram, specifications)
          return qualified if qualified

          standard_box_scene(diagram, specifications)
        end

        def hide_members_grid_scene(diagram, specifications)
          return unless hide_members_grid_family?(diagram)

          visible, hidden = specifications.partition do |item|
            item[:member_rows].any?
          end
          ordered = visible + hidden
          rows = ordered.each_slice(2).to_a
          boxes = hide_members_grid_boxes(rows)
          width, height = chain_dimensions(boxes)
          Scene.new(width: width, height: height, boxes: boxes,
                    relations: [], frames: [])
        end

        def hide_members_grid_family?(diagram)
          diagram.classes.size > 1 && diagram.notes.empty? &&
            standalone_diagram?(diagram) &&
            diagram.directives.include?("hide members") &&
            diagram.classes.any? { |klass| klass.body.any? }
        end

        def hide_members_grid_boxes(rows)
          row_widths = rows.map { |row| hide_members_row_width(row) }
          widest = row_widths.max
          tops = isolated_class_kind_row_tops(rows)
          rows.each_with_index.flat_map do |row, index|
            left = MARGIN + ((widest - row_widths.fetch(index)) / 2)
            hide_members_grid_row(row, left, tops.fetch(index))
          end
        end

        def hide_members_row_width(row)
          row.sum { |item| item[:width] } +
            (ISOLATED_KIND_COLUMN_GAP * (row.size - 1))
        end

        def hide_members_grid_row(row, left, top)
          height = row.map { |item| item[:height] }.max
          row.each_with_object([]) do |item, boxes|
            y = top + ((height - item[:height]) / 2)
            boxes << build_box(item, left, y, item[:width])
            left += item[:width] + ISOLATED_KIND_COLUMN_GAP
          end
        end

        def isolated_class_kind_scene(diagram, specifications)
          return unless isolated_class_kind_family?(diagram)

          rows = specifications.each_slice(2).to_a
          boxes = isolated_class_kind_boxes(rows)
          width, height = chain_dimensions(boxes)
          Scene.new(width: width, height: height, boxes: boxes,
                    relations: [], frames: [])
        end

        def isolated_class_kind_family?(diagram)
          diagram.classes.size > 1 && diagram.notes.empty? &&
            standalone_diagram?(diagram) &&
            diagram.classes.any? { |klass| klass.kind != :class }
        end

        def isolated_class_kind_boxes(rows)
          widths = isolated_class_kind_column_widths(rows)
          tops = isolated_class_kind_row_tops(rows)
          rows.each_with_index.flat_map do |row, row_index|
            isolated_class_kind_row(row, widths, tops.fetch(row_index))
          end
        end

        def isolated_class_kind_column_widths(rows)
          columns = rows.map(&:size).max
          Array.new(columns) do |column|
            rows.filter_map { |row| row[column]&.fetch(:width) }.max
          end
        end

        def isolated_class_kind_row_tops(rows)
          heights = rows.map { |row| row.map { |item| item[:height] }.max }
          heights.each_with_object([MARGIN]) do |height, tops|
            tops << (tops.last + height + ISOLATED_KIND_ROW_GAP)
          end
        end

        def isolated_class_kind_row(row, widths, top)
          lefts = isolated_class_kind_column_lefts(widths)
          height = row.map { |item| item[:height] }.max
          row.each_with_index.map do |item, column|
            origin = isolated_class_kind_origin(item, lefts.fetch(column),
                                                widths.fetch(column),
                                                [top, height])
            build_box(item, *origin, item[:width])
          end
        end

        def isolated_class_kind_origin(item, left, cell_width, (top, height))
          [left + ((cell_width - item[:width]) / 2),
           top + ((height - item[:height]) / 2)]
        end

        def isolated_class_kind_column_lefts(widths)
          widths.each_with_object([MARGIN]) do |width, lefts|
            lefts << (lefts.last + width + ISOLATED_KIND_COLUMN_GAP)
          end
        end

        def standard_box_scene(diagram, specifications)
          chain = RankChain.for(diagram)
          return chain_scene(diagram, chain, specifications) if chain
          return noted_scene(diagram, specifications) if diagram.notes.any?

          hierarchy = RankHierarchy.for(diagram)
          if hierarchy
            return hierarchy_scene(diagram, hierarchy, specifications)
          end

          grid_scene(diagram, specifications)
        end

        def grid_scene(diagram, specifications)
          box_width = widest_box(specifications)
          boxes = position_boxes(rows_by_package(specifications, diagram),
                                 box_width, stable_centers?(diagram),
                                 intrinsic_box_widths?(diagram), diagram)
          boxes = align_package_relation_targets(diagram, boxes,
                                                 specifications)

          build_scene(diagram, boxes, box_width)
        end

        def box_specifications(diagram)
          classes = diagram.classes.map do |klass|
            box_specification(klass, diagram)
          end
          classes + note_specifications(diagram.notes)
        end

        def qualified_scene(diagram, specifications)
          qualified = QualifiedAssociationLayout.for(diagram)
          if qualified
            qualified_association_scene(diagram, qualified, specifications)
          end
        end

        def qualified_association_scene(diagram, qualified, specifications)
          sizes = qualified.constrained_sizes(qualified_sizes(specifications))
          specifications = resized_specifications(specifications, sizes)
          corners = qualified.place(sizes, [MARGIN, MARGIN])
          boxes = chain_boxes(specifications, corners, sizes)
          width, height = chain_dimensions(boxes)
          @qualified_layout_active = true
          @qualified_route_middle = qualified_route_middle(boxes)
          Scene.new(width: width, height: height, boxes: boxes, frames: [],
                    relations: scene_relations(diagram, boxes))
        end

        def resized_specifications(specifications, sizes)
          specifications.map do |item|
            width, height = sizes.fetch(item[:id])
            item.merge(width: width, height: height)
          end
        end

        def qualified_sizes(specifications)
          specifications.to_h do |item|
            [item[:id], [item[:width], item[:height]]]
          end
        end

        def qualified_route_middle(boxes)
          boxes.sum { |box| box.y + (box.height / 2) } / boxes.size
        end

        def chain_scene(diagram, chain, specifications)
          sizes = chain_sizes(specifications, diagram)
          corners, nodes = chain.place(sizes, [MARGIN, MARGIN],
                                       label_widths(diagram))
          boxes = chain_boxes(specifications, corners, sizes)
          width, height = chain_dimensions(boxes)
          Scene.new(width: width, height: height,
                    boxes: boxes, frames: [],
                    relations: scene_relations(diagram, boxes, nodes))
        end

        def hierarchy_scene(diagram, hierarchy, specifications)
          items = specifications.reject { |item| item[:note] }
          sizes = item_sizes(items)
          corners = hierarchy.place(sizes, [MARGIN, MARGIN])
          boxes = chain_boxes(items, corners, sizes)
          width, height = chain_dimensions(boxes)
          Scene.new(width: width, height: height, boxes: boxes, frames: [],
                    relations: scene_relations(diagram, boxes))
        end

        def item_sizes(items)
          items.to_h { |item| [item[:id], [item[:width], item[:height]]] }
        end

        # Classes placed as without notes, then the notes around them; the
        # whole drawing is moved so its top left corner keeps the margin.
        def noted_scene(diagram, specifications)
          items = specifications.reject { |item| item[:note] }
          sizes, corners = noted_class_corners(diagram, items)
          boxes = margined_boxes(diagram, items, sizes, corners)
          width, height = chain_dimensions(boxes)
          Scene.new(width: width, height: height, boxes: boxes, frames: [],
                    relations: scene_relations(diagram, boxes))
        end

        # The class boxes and their notes, moved so the drawing's top left
        # corner keeps the margin.
        def margined_boxes(diagram, items, sizes, corners)
          boxes = chain_boxes(items, corners, sizes)
          shift = noted_shift(boxes + noted_boxes(diagram, boxes))
          boxes = chain_boxes(items, shifted_corners(corners, shift), sizes)
          boxes + noted_boxes(diagram, boxes)
        end

        def noted_class_corners(diagram, items)
          hierarchy = RankHierarchy.for(diagram)
          return hierarchy_corners(hierarchy, items) if hierarchy

          grid_corners(diagram, items)
        end

        def hierarchy_corners(hierarchy, items)
          sizes = item_sizes(items)
          [sizes, hierarchy.place(sizes, [MARGIN, MARGIN])]
        end

        def grid_corners(diagram, items)
          rows = rows_by_package(items, diagram)
          placed = position_boxes(rows, widest_box(items),
                                  stable_centers?(diagram),
                                  intrinsic_box_widths?(diagram), diagram)
          [placed.to_h { |box| [box.id, [box.width, box.height]] },
           placed.to_h { |box| [box.id, [box.x, box.y]] }]
        end

        def noted_boxes(diagram, boxes)
          NoteLayout.new(diagram, method(:note_line_width),
                         method(:member_text_width)).place(boxes)
        end

        def member_text_width(text)
          standard_text_width(text, font_size)
        end

        def note_line_width(text)
          measure_text(text, font_size: font_size * (13.0 / 14.0))[:width]
        end

        def noted_shift(boxes)
          [MARGIN - boxes.map(&:x).min, MARGIN - boxes.map(&:y).min]
        end

        def shifted_corners(corners, shift)
          corners.transform_values do |(left, top)|
            [left + shift.first, top + shift.last]
          end
        end

        def chain_sizes(specifications, diagram)
          widest = widest_box(specifications)
          intrinsic_widths = intrinsic_box_widths?(diagram)
          specifications.to_h do |item|
            width = if compact_empty_item?(item, diagram) || intrinsic_widths
                      item[:width]
                    else
                      widest
                    end
            [item[:id], [width, item[:height]]]
          end
        end

        def chain_dimensions(boxes)
          [far_edge(boxes) { |box| box.x + box.width },
           far_edge(boxes) { |box| box.y + box.height }]
        end

        def chain_boxes(specifications, corners, sizes)
          specifications.map do |item|
            left, top = corners.fetch(item[:id])
            build_box(item, left, top, sizes.fetch(item[:id]).first)
          end
        end

        def member_note_family?(diagram)
          return false unless diagram.classes.one? && diagram.notes.any?
          return false unless standalone_diagram?(diagram)

          klass = diagram.classes.first
          plain_class?(klass) && member_notes?(diagram.notes, klass)
        end

        def class_note_pair_family?(diagram)
          classes = diagram.classes
          notes = diagram.notes
          class_note_pair_counts?(classes, notes) &&
            standalone_diagram?(diagram) &&
            classes.all? { |klass| class_note_class?(klass) } &&
            paired_class_notes?(classes, notes)
        end

        def class_note_pair_counts?(classes, notes)
          classes.size > 1 && notes.size == classes.size
        end

        def paired_class_notes?(classes, notes)
          return false unless class_level_right_notes?(notes)

          notes.map(&:target).sort == classes.map(&:name).sort
        end

        def class_note_class?(klass)
          plain_class?(klass) && klass.body.empty?
        end

        def class_level_right_notes?(notes)
          notes.all? { |note| note.member.nil? && note.side == :right }
        end

        def standalone_diagram?(diagram)
          diagram.relations.empty? && diagram.junctions.empty? &&
            diagram.packages.empty?
        end

        def plain_class?(klass)
          klass.kind == :class && klass.stereotypes.empty? &&
            klass.generics.nil?
        end

        def member_notes?(notes, klass)
          members = klass.body.map(&:name)
          notes.all? do |note|
            note.member && members.include?(note.member) &&
              note.target == klass.name && note.side == :right
          end
        end

        def member_note_scene(diagram)
          klass = diagram.classes.first
          class_box = member_note_class_box(klass)
          notes = member_note_boxes(diagram, klass, class_box)
          boxes = [class_box, *notes]
          boxes_only_scene(boxes)
        end

        def class_note_pair_scene(diagram)
          specifications = diagram.classes.to_h do |klass|
            [klass.name, box_specification(klass, diagram)]
          end
          notes = indexed_class_notes(diagram.notes)
          boxes = place_class_note_pairs(diagram.classes, specifications,
                                         notes)
          boxes_only_scene(boxes)
        end

        def boxes_only_scene(boxes)
          Scene.new(width: far_edge(boxes) { |box| box.x + box.width },
                    height: far_edge(boxes) { |box| box.y + box.height },
                    boxes: boxes, relations: [], frames: [])
        end

        def indexed_class_notes(notes)
          notes.each_with_index.to_h do |note, index|
            [note.target, [note, index]]
          end
        end

        def place_class_note_pairs(classes, specifications, notes)
          cursor = MARGIN
          classes.flat_map do |klass|
            item = specifications.fetch(klass.name)
            class_box = build_box(item, cursor, MARGIN, item[:width])
            note, index = notes.fetch(klass.name)
            note_box = class_level_note_box(note, index, class_box)
            cursor = note_box.x + note_box.width + CLASS_NOTE_GAP
            [class_box, note_box]
          end
        end

        def class_level_note_box(note, index, class_box)
          geometry = class_level_note_geometry(note, class_box)
          Scene::Box.new(
            id: "note-#{index}", **geometry,
            texts: member_note_texts(note, geometry[:x], geometry[:y]),
            separators: [class_level_note_pointer(class_box, geometry)],
            kind: "member_note", fill: note.color
          )
        end

        def class_level_note_geometry(note, class_box)
          height = member_note_height(note)
          {
            x: class_box.x + class_box.width + CLASS_NOTE_GAP,
            y: class_box.y + ((class_box.height - height) / 2),
            width: class_level_note_width(note), height: height
          }
        end

        def class_level_note_pointer(class_box, geometry)
          segment(class_box.x + class_box.width,
                  class_box.y + (class_box.height / 2),
                  geometry[:x], geometry[:y] + (geometry[:height] / 2))
        end

        def class_level_note_width(note)
          size = font_size * (13.0 / 14.0)
          widths = note.lines.map do |line|
            Drawing::Face.widest_line(line, size: size)
          end
          widths.max.to_f + 21.0
        end

        def far_edge(boxes, &)
          boxes.map(&).max + MARGIN
        end

        def member_note_class_box(klass)
          width = member_note_class_width(klass)
          height = MEMBER_NOTE_CLASS_HEIGHT +
            (klass.body.size * MEMBER_NOTE_ROW_HEIGHT)
          texts = member_note_class_texts(klass, width)
          Scene::Box.new(
            id: klass.name, x: MARGIN, y: MARGIN, width: width, height: height,
            texts: texts, separators: [member_note_separator(width)],
            kind: "class"
          )
        end

        def member_note_separator(width)
          separator_y = MARGIN + MEMBER_NOTE_CLASS_HEIGHT -
            MEMBER_NOTE_ROW_HEIGHT
          segment(MARGIN, separator_y, MARGIN + width, separator_y)
        end

        def member_note_class_width(klass)
          # The pinned renderer's sans-serif is wider than the deterministic
          # Arial table on this machine. This factor is measured across every
          # member row in the reference-backed group2814 family.
          name = plantuml_text_width(klass.name) + 32.0
          members = klass.body.map do |member|
            plantuml_text_width(member_text(member)) +
              (MEMBER_NOTE_SIDE_PADDING * 2)
          end
          [name, *members].max
        end

        def member_note_class_texts(klass, width)
          title = scene_text(klass.name, MARGIN + (width / 2), MARGIN + 21.291,
                             "class_name", "middle")
          members = klass.body.each_with_index.map do |member, index|
            member_note_row_text(member, index)
          end
          [title, *members]
        end

        def member_note_row_text(member, index)
          vertical = MARGIN + 49.535 + (index * MEMBER_NOTE_ROW_HEIGHT)
          role = member.type_position == :prefix ? "member_prefix" : "member"
          scene_text(member_text(member), MARGIN + MEMBER_NOTE_SIDE_PADDING,
                     vertical, role, "start")
        end

        def member_note_boxes(diagram, klass, class_box)
          tops = member_note_tops(diagram.notes, class_box)
          fill = shared_member_note_fill(diagram)
          diagram.notes.each_with_index.map do |note, index|
            box = member_note_box(note, index, klass, class_box, tops[index])
            box.tap { |placed| placed.fill = fill }
          end
        end

        def member_note_tops(notes, class_box)
          heights = notes.map { |note| member_note_height(note) }
          first = first_note_top(class_box, heights)
          heights.each_with_object([first]) do |height, tops|
            tops << (tops.last + (height + MEMBER_NOTE_STACK_GAP))
          end
        end

        def first_note_top(class_box, heights)
          total = heights.sum +
            (MEMBER_NOTE_STACK_GAP * (heights.size - 1))
          class_box.y + ((class_box.height - total) / 2) - 5.0
        end

        def member_note_box(note, index, klass, class_box, top)
          height = member_note_height(note)
          left = class_box.x + class_box.width + MEMBER_NOTE_BODY_GAP
          pointer = member_note_pointer(note, klass, class_box,
                                        [left, top + (height / 2)])
          Scene::Box.new(id: "note-#{index}", x: left, y: top,
                         width: member_note_width(note), height: height,
                         texts: member_note_texts(note, left, top),
                         separators: [pointer], kind: "member_note")
        end

        def member_note_width(note)
          note.lines.map { |line| plantuml_note_width(line) }.max.to_f + 21.0
        end

        def member_note_pointer(note, klass, class_box, anchor)
          target = member_note_target(note, klass, class_box)
          segment(target[0], target[1], anchor[0], anchor[1])
        end

        def member_note_target(note, klass, class_box)
          index = klass.body.index { |member| member.name == note.member }
          [member_note_target_x(klass.body.fetch(index), class_box),
           class_box.y + 44.244 + (index * MEMBER_NOTE_ROW_HEIGHT)]
        end

        def member_note_target_x(member, class_box)
          class_box.x + MEMBER_NOTE_SIDE_PADDING +
            plantuml_text_width(member_text(member))
        end

        def member_note_texts(note, left, top)
          note.lines.each_with_index.map do |line, index|
            vertical = top + 17.568 + (index * MEMBER_NOTE_LINE_HEIGHT)
            scene_text(line, left + 6.0, vertical, "member_note", "start")
          end
        end

        def member_note_height(note)
          10.0 + ([note.lines.size, 1].max * MEMBER_NOTE_LINE_HEIGHT)
        end

        def shared_member_note_fill(diagram)
          # PlantUML 1.2026.6 gives one side's shared tips entity the last
          # note's paint. Preserve that pinned visible behavior for the stack.
          note = diagram.notes.last
          note.color || stereotype_note_fill(note.stereotype,
                                             diagram.directives)
        end

        def stereotype_note_fill(stereotype, directives)
          return unless stereotype

          name = stereotype.delete_prefix("<<").delete_suffix(">>")
          prefix = "skinparam\\s+noteBackgroundColor<<#{Regexp.escape(name)}>>"
          pattern = /\A#{prefix}\s+(\S+)\z/i
          directive = directives.reverse.find { |line| line.match?(pattern) }
          directive&.match(pattern)&.[](1)
        end

        def plantuml_text_width(text)
          measure_text(text, font_size: font_size)[:width] *
            MEMBER_NOTE_TEXT_SCALE
        end

        def plantuml_note_width(text)
          measure_text(text, font_size: font_size * (13.0 / 14.0))[:width] *
            MEMBER_NOTE_TEXT_SCALE
        end

        def dress(diagram, scene)
          measure = lambda do |text, size|
            measure_text(text, font_size: size)[:width]
          end
          ClassHeader.apply(diagram, scene,
                            ->(text) { measure.call(text, font_size) })
          captions = CaptionLayout.new(diagram, normal_size: font_size,
                                                measure: measure)
          captions.dress(scene)
        end

        def build_scene(diagram, boxes, box_width)
          frames = scene_frames(diagram, boxes)
          width, height = scene_dimensions(diagram, boxes, frames, box_width)
          Scene.new(width: width, height: height, boxes: boxes,
                    relations: scene_relations(diagram, boxes + frames),
                    frames: frames)
        end

        def scene_dimensions(diagram, boxes, frames, box_width)
          unless package_endpoint_relation?(diagram)
            return [canvas_width(boxes, box_width),
                    scene_height(diagram, boxes)]
          end

          figures = boxes + frames
          [package_extent(figures, :x, :width),
           package_extent(figures, :y, :height)]
        end

        def package_extent(figures, origin, size)
          figures.map do |item|
            item.public_send(origin) + item.public_send(size)
          end.max + PACKAGE_CANVAS_EDGE
        end

        def scene_height(diagram, boxes)
          room = PackageFrames::OPEN + PackageFrames::CLOSE
          canvas_height(box_rows(boxes)) + (diagram.packages.size * room)
        end

        def scene_frames(diagram, boxes)
          PackageFrames.new(diagram, method(:measured_width)).call(boxes)
        end

        # `nodes` holds each junction node as `[x, y, width, height]` by the
        # index of its relation; without one the legs meet at the middle.
        def scene_relations(diagram, boxes, nodes = {})
          build_relations(diagram, boxes, nodes)
        end

        def box_specification(klass, diagram)
          member_rows = klass.body.map { |member| member_text(member) }
          names, generic = qualified_box_names(klass, diagram)
          record = box_record(klass.name, header_rows(klass) + names,
                              member_rows)
          details = { member_rows: member_rows, names: names, generic: generic }
          complete_box_specification(record, klass, diagram, details)
        end

        def qualified_box_names(klass, diagram)
          qualified = !QualifiedAssociationLayout.for(diagram).nil?
          names = name_rows(klass, separate_generics: qualified)
          generic = klass.generics if qualified
          [generic ? names[0...-1] : names, generic]
        end

        def complete_box_specification(record, klass, diagram, details)
          record = proportional_member_box(record, klass, diagram, details)
          record = compartmented_empty_box(record, details[:member_rows],
                                           diagram)
          record = compact_empty_box(record, details[:member_rows], diagram)
          record = smetana_hide_circle_box(record, klass, diagram, details)
          adjust_plain_empty_width(record, klass, diagram, details[:names])
          record = package_relation_box(record, klass, diagram, details)
          record = multiline_title_box(record, klass, details)
          record = isolated_box_sizes(record, klass, diagram, details)
          with_box_context(record, klass, diagram, details)
        end

        def with_box_context(record, klass, diagram, details)
          record.merge(name_rows: details[:names].size,
                       floating_generic: details[:generic],
                       **box_context(klass, diagram))
        end

        # A box of one name row and some members is as wide as its widest
        # proportional row and as tall as the reference row pitch makes it.
        def proportional_member_box(record, klass, diagram, details)
          rows = details[:member_rows]
          return record if rows.empty? || record.fetch(:title_rows).size > 1

          record.merge(
            width: [*standard_title_widths(details[:names]),
                    *member_row_widths(klass, rows, diagram)].max,
            height: pitched_member_height(klass, diagram, rows),
            compact_members: true,
          )
        end

        MEMBER_PORTIONS = /\A(?:hide|show)\b.*\b(?:members|attributes|methods|
                          fields)\z/xi
        private_constant :MEMBER_PORTIONS

        # An empty field or method group keeps its 8-high compartment unless
        # a `hide` or `show` line is in play.
        def empty_gaps?(diagram)
          diagram.directives.none? { |line| line.match?(MEMBER_PORTIONS) }
        end

        def member_row_widths(klass, rows, diagram)
          insets = member_insets_for(klass, diagram)
          klass.body.each_index.filter_map do |index|
            next unless insets[index]

            member_row_width(rows[index], klass.body[index], insets[index])
          end
        end

        def member_insets_for(klass, diagram)
          MemberIcon.insets(klass.body.map(&:kind),
                            klass.body.map(&:visibility),
                            MemberIcon.enabled?(diagram.directives))
        end

        def member_row_width(row, member, inset)
          text = MemberIcon.visible_text(row, member.visibility,
                                         inset == MemberIcon::TEXT_INSET)
          inset + standard_text_width(text, font_size) +
            MemberIcon::TEXT_PLAIN
        end

        def isolated_box_sizes(record, klass, diagram, details)
          record = isolated_standard_box(record, klass, diagram, details)
          record = isolated_class_kind_box(record, diagram, details)
          record = hide_members_grid_box(record, diagram, details)
          qualified_association_box(record, klass, diagram, details)
        end

        def package_relation_box(record, klass, diagram, details)
          return record unless package_endpoint_relation?(diagram)
          return record unless plain_class?(klass) && klass.body.empty? &&
            details[:names].one?

          record.merge(width: standard_title_widths(details[:names]).max,
                       height: MEMBER_NOTE_CLASS_HEIGHT)
        end

        def qualified_association_box(record, klass, diagram, details)
          return record unless QualifiedAssociationLayout.for(diagram)

          record.merge(title_rows: details[:names],
                       width: qualified_box_width(klass, diagram, details),
                       height: qualified_height_with_members(
                         klass, diagram, details
                       ),
                       compact_members: details[:member_rows].any?)
        end

        # A qualified box that carries members grows by their rows; its fixed
        # height is only right for a box that is a bare title.
        def qualified_height_with_members(klass, diagram, details)
          height = qualified_box_height(diagram, details[:generic])
          rows = details[:member_rows].size
          return height if rows.zero?

          base = qualified_compact?(diagram) ? COMPACT_RULE_BASE_HEIGHT : height
          gaps = member_group_boundaries(klass.body.map(&:kind)).size
          base + (rows * MEMBER_NOTE_ROW_HEIGHT) + (gaps * COMPACT_GROUP_GAP)
        end

        # Indexes of the rows that open a method group after a field group.
        def member_group_boundaries(kinds)
          kinds.each_cons(2).with_index(1).filter_map do |(left, right), index|
            index if left == :field && right == :method
          end
        end

        def qualified_box_width(klass, diagram, details)
          widths = standard_title_widths(details[:names])
          widths << qualified_generic_width(widths.max, details[:generic])
          widths << qualified_incident_width(klass, diagram)
          widths.concat(member_widths(details[:member_rows]))
          widths.compact.max
        end

        def member_widths(rows)
          rows.map { |row| measured_width(row) + (BOX_PADDING * 2) }
        end

        def qualified_generic_width(title_width, generic)
          return unless generic

          title_width + standard_text_width(generic,
                                            QUALIFIED_GENERIC_FONT_SIZE) +
            QUALIFIED_GENERIC_GAP
        end

        def qualified_incident_width(klass, diagram)
          text = incident_qualifiers(klass, diagram).max_by(&:length)
          return unless text

          standard_text_width(text, font_size) + qualifier_allowance(diagram)
        end

        def incident_qualifiers(klass, diagram)
          diagram.relations.filter_map do |relation|
            next unless relation.direction.nil?
            next unless [relation.left, relation.right].include?(klass.name)

            qualified_text_at(relation, klass.name)
          end
        end

        def qualifier_allowance(diagram)
          if qualified_compact?(diagram)
            COMPACT_QUALIFIER_ALLOWANCE
          else
            QUALIFIED_QUALIFIER_ALLOWANCE
          end
        end

        def qualified_text_at(relation, name)
          content = if relation.left == name
                      relation.left_multiplicity
                    else
                      relation.right_multiplicity
                    end
          return unless content&.start_with?("[")

          content.delete_prefix("[").delete_suffix("]")
            .split("\\n").max_by(&:length)
        end

        def qualified_box_height(diagram, generic)
          return HIDDEN_MEMBER_EMPTY_HEIGHT if qualified_compact?(diagram)

          generic ? QUALIFIED_GENERIC_HEIGHT : QUALIFIED_BOX_HEIGHT
        end

        def qualified_compact?(diagram)
          diagram.directives.include?("hide empty members")
        end

        def hide_members_grid_box(record, diagram, details)
          return record unless hide_members_grid_family?(diagram)

          members = details[:member_rows]
          widths = standard_title_widths(details[:names]) +
            isolated_class_kind_member_widths(members)
          record.merge(width: widths.max, compact_members: true,
                       height: hide_members_box_height(members))
        end

        def hide_members_box_height(members)
          return HIDDEN_MEMBER_EMPTY_HEIGHT if members.empty?

          RESHOWN_MEMBER_BASE_HEIGHT +
            (members.size * MEMBER_NOTE_ROW_HEIGHT)
        end

        def isolated_class_kind_box(record, diagram, details)
          return record unless isolated_class_kind_family?(diagram)

          widths = standard_title_widths(details[:names]) +
            isolated_class_kind_member_widths(details[:member_rows])
          record.merge(
            title_rows: details[:names], width: widths.max,
            compact_members: true,
            height: MEMBER_NOTE_CLASS_HEIGHT +
              (details[:member_rows].size * MEMBER_NOTE_ROW_HEIGHT)
          )
        end

        def isolated_class_kind_member_widths(rows)
          rows.map do |row|
            visible = row.sub(/\A[+\-#~]/, "")
            standard_text_width(visible, font_size) +
              ISOLATED_KIND_MEMBER_ALLOWANCE
          end
        end

        # A class with no members keeps its two 8-high compartments below
        # the name, which ClassHeader rules.
        def compartmented_empty_box(record, member_rows, diagram)
          return record unless member_rows.empty? && empty_gaps?(diagram)
          return record unless record.fetch(:title_rows).one?

          record.merge(height: record.fetch(:height) + EMPTY_COMPARTMENTS_EXTRA)
        end

        def compact_empty_box(record, member_rows, diagram)
          return record unless member_rows.empty?
          return record unless compact_empty_members?(diagram)

          record.merge(
            height: record[:height] - EMPTY_MEMBER_COMPARTMENT,
            width: record[:width] + EMPTY_CLASS_WIDTH_EXTRA,
          )
        end

        def compact_empty_members?(diagram)
          RankChain.engine(diagram) == :smetana &&
            diagram.directives.include?("hide empty members")
        end

        def compact_empty_item?(item, diagram)
          compact_empty_members?(diagram) && item[:member_rows]&.empty?
        end

        def smetana_hide_circle_box(record, klass, diagram, details)
          return record unless smetana_hide_circle_class?(klass, diagram)

          record.merge(
            width: hide_circle_box_width(details),
            compact_members: true,
            height: HIDE_CIRCLE_BASE_HEIGHT +
              (details[:member_rows].size * MEMBER_NOTE_ROW_HEIGHT),
          )
        end

        def hide_circle_box_width(details)
          [
            *standard_row_widths(details[:names], font_size,
                                 HIDE_CIRCLE_TITLE_ALLOWANCE),
            *standard_row_widths(details[:member_rows], font_size,
                                 HIDE_CIRCLE_MEMBER_ALLOWANCE),
          ].max
        end

        def smetana_hide_circle_class?(klass, diagram)
          RankChain.engine(diagram) == :smetana && plain_class?(klass) &&
            klass.package.nil? &&
            diagram.directives.any? { |line| line.match?(/\Ahide circle\z/i) }
        end

        def adjust_plain_empty_width(specification, klass, diagram, names)
          if plain_empty_class?(klass, diagram, names)
            specification[:width] = plain_empty_class_width(names.first)
          elsif heterogeneous_smetana_empty_class?(klass, diagram, names)
            specification[:width] = standard_title_widths(names).max
            specification[:height] = MEMBER_NOTE_CLASS_HEIGHT
          end
        end

        def plain_empty_class?(klass, diagram, names)
          return false unless simple_empty_class?(klass, names)
          return false unless uniform_empty_class_lengths?(diagram)

          diagram.directives.none? do |line|
            line.match?(/\Ahide[ \t]+(?:circle|empty[ \t]+members)\z/i)
          end
        end

        def simple_empty_class?(klass, names)
          plain_class?(klass) && klass.body.empty? && klass.package.nil? &&
            names.one?
        end

        def uniform_empty_class_lengths?(diagram)
          names = diagram.classes.map do |candidate|
            rows = name_rows(candidate)
            return false unless simple_empty_class?(candidate, rows)

            rows.first
          end
          names.map(&:length).uniq.one?
        end

        def heterogeneous_smetana_empty_class?(klass, diagram, names)
          simple_empty_class?(klass, names) &&
            heterogeneous_smetana_empty_classes?(diagram)
        end

        def heterogeneous_smetana_empty_classes?(diagram)
          return false unless plain_smetana_diagram?(diagram)

          names = simple_empty_class_names(diagram)
          names && names.map(&:length).uniq.size > 1
        end

        def plain_smetana_diagram?(diagram)
          RankChain.engine(diagram) == :smetana &&
            !compact_empty_members?(diagram) &&
            diagram.directives.none? { |line| hide_or_show?(line) }
        end

        def simple_empty_class_names(diagram)
          diagram.classes.map do |candidate|
            rows = name_rows(candidate)
            return unless simple_empty_class?(candidate, rows)

            rows.first
          end
        end

        def hide_or_show?(line)
          line.match?(/\A(?:hide|show)\b/i)
        end

        def plain_empty_class_width(name)
          title_width = Drawing::Face.widest_line(name, size: font_size)
          [((title_width * 2).round / 2.0) + 32.0,
           EMPTY_CLASS_MIN_WIDTH].max
        end

        def multiline_title_box(record, klass, details)
          return record unless multiline_title_box?(record, klass, details)

          rows = record.fetch(:title_rows).size
          height = MULTILINE_TITLE_VERTICAL_ALLOWANCE +
            (rows * MULTILINE_TITLE_ROW_HEIGHT)
          width = multiline_title_width(record.fetch(:title_rows))
          record.merge(width: width, height: height, compact_title_rows: true)
        end

        def multiline_title_box?(record, klass, details)
          details[:member_rows].empty? && record.fetch(:title_rows).size > 1 &&
            header_rows(klass).empty?
        end

        def multiline_title_width(rows)
          widths = rows.map do |row|
            measure_text(row, font_size: font_size)[:width]
          end
          widths.max.to_f + MULTILINE_TITLE_SIDE_ALLOWANCE
        end

        def isolated_standard_box(record, klass, diagram, details)
          return record unless isolated_standard_box?(klass, diagram, details)

          record = record.merge(
            width: isolated_standard_width(klass, details),
            height: isolated_standard_height(klass, diagram,
                                             details[:member_rows]),
            compact_members: header_rows(klass).empty?,
          )
          stereotype_headed(record, klass, details)
        end

        # A lone class with one stereotype takes the jar's header: circle
        # at the left, stereotype above the name, rows packed from the foot.
        def stereotype_headed(record, klass, details)
          return record unless StereotypeHead.applies?(klass,
                                                       circle: @kind_in_spot)

          row = "«#{klass.stereotypes.first}»"
          sizes = stereotype_head_sizes(row, details[:names].first)
          width = [StereotypeHead.width(*sizes),
                   *standard_member_widths(details[:member_rows])].max
          record.merge(width: width, compact_members: true,
                       stereotype_head: { row: row, sizes: sizes })
        end

        def stereotype_head_sizes(row, name)
          [standard_text_width(row, font_size * 0.85),
           standard_text_width(name, font_size)]
        end

        def isolated_standard_box?(klass, diagram, details)
          lone_standard_class?(klass, diagram) &&
            (details[:member_rows].any? || klass.stereotypes.any?)
        end

        def lone_standard_class?(klass, diagram)
          diagram.classes.one? && diagram.notes.empty? &&
            standalone_diagram?(diagram) && klass.kind == :class &&
            klass.generics.nil?
        end

        def isolated_standard_width(klass, details)
          [standard_title_widths(details[:names]),
           standard_header_widths(klass),
           standard_member_widths(details[:member_rows])].flatten.max
        end

        def standard_title_widths(rows)
          standard_row_widths(rows, font_size,
                              STANDARD_TITLE_SIDE_ALLOWANCE)
        end

        def standard_header_widths(klass)
          rows = header_rows(klass).map do |row|
            row.gsub(/<<([^<>]+)>>/, '«\1»')
          end
          standard_row_widths(rows, font_size * (12.0 / 14.0),
                              STANDARD_TITLE_SIDE_ALLOWANCE)
        end

        def standard_member_widths(rows)
          standard_row_widths(rows, font_size,
                              STANDARD_MEMBER_SIDE_ALLOWANCE)
        end

        def standard_row_widths(rows, size, allowance)
          rows.map { |row| standard_text_width(row, size) + allowance }
        end

        def standard_text_width(text, size)
          Drawing::Face.widest_line(text, size: size)
        end

        def isolated_standard_height(klass, diagram, member_rows)
          headers = header_rows(klass)
          unless headers.empty?
            return MEMBER_NOTE_CLASS_HEIGHT +
                (member_rows.size * MEMBER_NOTE_ROW_HEIGHT) +
                (headers.size * STANDARD_STEREOTYPE_ROW_HEIGHT)
          end

          pitched_member_height(klass, diagram, member_rows)
        end

        def pitched_member_height(klass, diagram, member_rows)
          PROPORTIONAL_MEMBER_BASE_HEIGHT +
            MemberPitch.layout(klass.body.map(&:kind), member_rows,
                               gaps: empty_gaps?(diagram)).last
        end

        def box_context(klass, diagram)
          modifiers = klass.body.map { |member| rule_modifiers(member) }
          { member_modifiers: modifiers, package: klass.package,
            member_kinds: klass.body.map(&:kind),
            member_visibilities: klass.body.map(&:visibility),
            icons_enabled: MemberIcon.enabled?(diagram.directives),
            empty_gaps: empty_gaps?(diagram),
            chain: diagram.package_chain(klass.package) }
        end

        # A separator row carries the pseudo-modifier :rule, which the box
        # draws as a line instead of text.
        def rule_modifiers(member)
          member.kind == :separator ? [:rule, member.type] : member.modifiers
        end

        def note_specifications(notes)
          notes.each_with_index.map do |note, index|
            rows = note.lines
            { id: "note-#{index}", note: note, rows: rows,
              width: measured_box_width(rows),
              height: (BOX_PADDING * 2) + ([rows.size, 1].max * ROW_HEIGHT) }
          end
        end

        def box_record(name, title_rows, member_rows)
          rows = title_rows + member_rows

          specification = { id: name }
          specification[:width] = measured_box_width(rows)
          specification[:height] = box_height(rows, member_rows)
          specification[:title_rows] = title_rows
          specification[:member_rows] = member_rows
          specification
        end

        def measured_box_width(rows)
          measured = rows.map { |text| measured_width(text) }
          measured.max.to_f + (BOX_PADDING * 2)
        end

        def box_height(rows, member_rows)
          height = (BOX_PADDING * 2) + (rows.size * ROW_HEIGHT)
          member_rows.empty? ? height : height + 6.0
        end

        def header_rows(klass)
          kind = ["<<#{klass.kind}>>"] unless spot_names_kind?(klass)
          tags = klass.stereotypes.map { |tag| "<<#{tag}>>" }
          [*kind, *(tags.join(" ") unless tags.empty?)]
        end

        # A class whose one-line name carries a circle needs no `<<kind>>`
        # row.
        def spot_names_kind?(klass)
          klass.kind == :class ||
            (@kind_in_spot && !ClassHeader.glyph(klass.kind).nil? &&
              ClassName.lines(klass.name).one?)
        end

        def name_rows(klass, separate_generics: false)
          *first, last = ClassName.lines(klass.name)
          return [*first, last, klass.generics] if separate_generics &&
            klass.generics

          [*first, (klass.generics ? "#{last}<#{klass.generics}>" : last)]
        end

        def measured_width(text)
          measure_text(text, font_size: font_size, monospace: true)[:width]
        end

        def font_size
          theme.typography.font_size_normal.to_f
        end

        def member_text(member)
          return member.name if member.kind == :separator

          name = member.name.dup
          name += "(#{member.parameters})" if member.parameters
          type = member.type
          content = if type && member.type_position == :prefix
                      "#{type} #{name}"
                    else
                      "#{name}#{"#{member.type_separator}#{type}" if type}"
                    end
          "#{visibility_mark(member.visibility)}#{content}"
        end

        def visibility_mark(visibility)
          MemberIcon.mark(visibility)
        end

        # Classes outside any package first, then each package's own classes
        # in the order the packages open (an outer package before the ones
        # inside it), every group padded to whole rows so a row holds one
        # group only.
        def rows_by_package(specifications, diagram)
          columns = column_count(specifications)
          package_groups(specifications, diagram).flat_map do |group|
            group.each_slice(columns).map { |row| pad(row, columns) }
          end
        end

        def package_groups(specifications, diagram)
          by_package = specifications.group_by { |item| item[:package] }
          ids = package_group_ids(diagram)
          ids.filter_map { |id| by_package[id] }
        end

        def package_group_ids(diagram)
          package_ids = diagram.packages.map(&:id)
          source_package = diagram.relations.any? do |relation|
            package_ids.include?(relation.left) &&
              !package_ids.include?(relation.right)
          end
          source_package ? [*package_ids, nil] : [nil, *package_ids]
        end

        def pad(row, columns)
          row + Array.new(columns - row.size)
        end

        def stable_centers?(diagram)
          horizontal = diagram.directives.include?("left to right direction")
          diagram.relations.any? do |relation|
            qualifiers = [relation.left_multiplicity,
                          relation.right_multiplicity]
            # PlantUML reserves relation-label lanes for qualifiers and for
            # fully annotated horizontal ends independently of class chrome.
            qualifiers.any? { |text| text&.start_with?("[") } ||
              (horizontal && annotated_ends?(relation))
          end
        end

        def annotated_ends?(relation)
          [relation.left_role, relation.right_role].compact.size == 2
        end

        def intrinsic_box_widths?(diagram)
          package_endpoint_relation?(diagram) || intrinsic_content?(diagram)
        end

        def intrinsic_content?(diagram)
          body = diagram.classes.any? { |klass| klass.body.any? }
          diagram.notes.any? || body ||
            heterogeneous_smetana_empty_classes?(diagram) ||
            diagram.directives.any? { |line| hide_or_show?(line) }
        end

        def position_boxes(rows, box_width, stable_centers, intrinsic_widths,
                           diagram)
          tops = row_tops(rows, diagram)
          placement = box_placement(rows, box_width, stable_centers,
                                    intrinsic_widths, diagram)
          rows.each_with_index.flat_map do |row, row_index|
            position_row(row, tops[row_index], box_width, placement)
          end
        end

        def box_placement(rows, box_width, stable_centers, intrinsic_widths,
                          diagram)
          { left: left_margin(rows, diagram),
            footprint: box_footprint(box_width, stable_centers),
            box_width: box_width,
            intrinsic_widths: intrinsic_widths,
            left_align: intrinsic_widths &&
              package_endpoint_relation?(diagram) }
        end

        def position_row(row, top, box_width, placement)
          row.each_with_index.filter_map do |item, column|
            x = box_left(item, column, placement)
            width = positioned_box_width(item, box_width, placement)
            build_box(item, x, top, width) if item
          end
        end

        def positioned_box_width(item, box_width, placement)
          return box_width unless placement[:intrinsic_widths]

          item&.fetch(:width)
        end

        def box_footprint(box_width, stable_centers)
          return box_width unless stable_centers

          [ANNOTATED_RELATION_SLOT_WIDTH, box_width].max
        end

        def box_left(item, column, placement)
          slot = placement[:left] +
            (column * (placement[:footprint] + COLUMN_GAP))
          return slot if placement[:left_align]

          width = if item && placement[:intrinsic_widths]
                    item.fetch(:width)
                  else
                    placement[:box_width]
                  end

          slot + ((placement[:footprint] - width) / 2)
        end

        def row_tops(rows, diagram)
          chains = rows.map { |row| row.compact.first[:chain] || [] }
          first = [top_margin(diagram) +
            frame_space([], chains.first, diagram)]
          steps = row_steps(rows, chains, diagram)
          steps.each_with_object(first) do |step, tops|
            tops << (tops.last + step)
          end
        end

        def row_steps(rows, chains, diagram)
          row_heights(rows).each_with_index.map do |height, index|
            below = chains[index + 1] || []
            space = frame_space(chains[index], below, diagram)
            height + row_gap(diagram, chains[index], below) + space
          end
        end

        def row_heights(rows)
          rows.map { |row| row.compact.map { |item| item[:height] }.max }
        end

        # The room for the frames closed on leaving the packages `above` and
        # opened on entering the packages `below`, each given outermost first.
        def frame_space(above, below, diagram)
          shared = above.zip(below).take_while { |a, b| a == b }.size
          closing = above.size - shared
          opening = below.size - shared
          if package_endpoint_relation?(diagram)
            return nested_frame_space(closing, opening)
          end

          (closing * PackageFrames::CLOSE) +
            (opening * PackageFrames::OPEN)
        end

        def nested_frame_space(closing, opening)
          PackageFrames.stack_close(closing) +
            PackageFrames.stack_open(opening)
        end

        def top_margin(diagram)
          package_endpoint_relation?(diagram) ? PACKAGE_CANVAS_MARGIN : MARGIN
        end

        def row_gap(diagram, above, below)
          crossing = above.empty? != below.empty?
          if package_endpoint_relation?(diagram) && crossing
            PACKAGE_OUTER_GAP
          else
            ROW_GAP
          end
        end

        def column_count(items)
          items.compact.size > 1 ? 2 : 1
        end

        # Room on the left for the deepest stack of package frames.
        def left_margin(rows, diagram)
          items = rows.flat_map(&:compact)
          depth = package_depth(items)
          if package_endpoint_relation?(diagram)
            return package_left_margin(depth)
          end

          [MARGIN, (depth * PackageFrames::SIDE) + 8.0].max
        end

        def package_depth(items)
          items.filter_map { |item| item[:chain]&.size }.max.to_i
        end

        def package_left_margin(depth)
          PACKAGE_CANVAS_MARGIN + PackageFrames.stack_side(depth)
        end

        def package_endpoint_relation?(diagram)
          PackageFrames.relation_layout?(diagram)
        end

        def align_package_relation_targets(diagram, boxes, specifications)
          by_name = boxes.to_h { |box| [box.id, box] }
          specs = specifications.to_h { |item| [item[:id], item] }
          replace_package_targets(diagram, by_name, specs)
          boxes.map { |box| by_name.fetch(box.id) }
        end

        def replace_package_targets(diagram, by_name, specs)
          diagram.relations.each do |relation|
            replacement = aligned_package_target(diagram, by_name, specs,
                                                 relation)
            by_name[replacement.id] = replacement if replacement
          end
        end

        def aligned_package_target(diagram, by_name, specs, relation)
          return unless package_source?(diagram, relation)

          target = by_name[relation.right]
          descendants = package_descendant_boxes(diagram, by_name,
                                                 relation.left)
          return unless target && descendants.any?

          build_aligned_package_target(diagram, specs, relation, target,
                                       descendants)
        end

        def build_aligned_package_target(diagram, specs, relation, target,
                                         descendants)
          left = package_target_left(diagram, descendants, target, relation)
          build_box(specs.fetch(target.id), left, target.y, target.width)
        end

        def package_source?(diagram, relation)
          diagram.packages.any? { |item| item.id == relation.left }
        end

        def package_target_left(diagram, descendants, target, relation)
          edge = descendants.map { |box| box.x + box.width }.max
          depth = package_relation_depth(diagram, relation.left)
          edge + PackageFrames.stack_side(depth) - (target.width / 2)
        end

        def package_descendant_boxes(diagram, by_name, package_id)
          diagram.classes.filter_map do |klass|
            chain = diagram.package_chain(klass.package)
            next unless chain.include?(package_id)

            by_name[klass.name]
          end
        end

        def package_relation_depth(diagram, package_id)
          diagram.classes.filter_map do |klass|
            chain = diagram.package_chain(klass.package)
            index = chain.index(package_id)
            chain.size - index if index
          end.max
        end

        def build_box(item, left, top, box_width)
          texts, separators = box_contents(item, left, top, box_width)

          Scene::Box.new(
            id: item[:id], x: left, y: top, width: box_width,
            height: item[:height], texts: texts, separators: separators,
            kind: item[:note] ? "note" : "class", fill: item[:note]&.color,
            spot: stereotype_spot(item, left, top)
          )
        end

        def stereotype_spot(item, left, top)
          return unless item[:stereotype_head]

          across, down = StereotypeHead.circle_centre
          Scene::Spot.new(kind: "class", cx: left + across, cy: top + down)
        end

        def note_texts(item, horizontal, vertical)
          item[:rows].each_with_index.map do |content, index|
            baseline = vertical + BOX_PADDING + font_size + (index * ROW_HEIGHT)
            scene_text(content, horizontal + BOX_PADDING, baseline,
                       "note", "start")
          end
        end

        def box_contents(item, horizontal, vertical, width)
          return [note_texts(item, horizontal, vertical), []] if item[:note]

          item = item.merge(compact_bottom: vertical + item[:height])
          texts, cursor = title_texts(item, horizontal, vertical, width)
          members, separators = member_contents(
            item, horizontal, cursor, width
          )
          [texts + members, separators]
        end

        def title_texts(item, horizontal, vertical, width)
          if item[:stereotype_head]
            return stereotype_head_texts(item, horizontal, vertical)
          end

          cursor = title_text_cursor(item, vertical)
          texts, cursor = title_text_rows(item, horizontal, width, cursor)
          texts << floating_generic_text(item, horizontal, vertical, width)
          [texts.compact, cursor]
        end

        def stereotype_head_texts(item, horizontal, vertical)
          head = item[:stereotype_head]
          centre = horizontal + StereotypeHead.centre(*head[:sizes])
          first, second = StereotypeHead.baselines
          [[scene_text(head[:row], centre, vertical + first, "kind", "middle"),
            scene_text(item[:title_rows].last, centre, vertical + second,
                       "class_name", "middle")], vertical + second]
        end

        def title_text_rows(item, horizontal, width, cursor)
          texts = item[:title_rows].each_with_index.map do |content, index|
            text = scene_text(content, horizontal + (width / 2), cursor,
                              title_role(item, index), "middle")
            cursor += title_row_height(item)
            text
          end
          [texts, cursor]
        end

        def title_text_cursor(item, vertical)
          if item[:compact_title_rows]
            return vertical + MULTILINE_TITLE_BASELINE
          end

          baseline = vertical + BOX_PADDING + font_size
          return baseline unless compact_single_title?(item)

          [baseline, compact_row_geometry(item)[:head] - 10.709].min
        end

        def compact_single_title?(item)
          item[:compact_members] && item[:title_rows].size == 1 &&
            item[:member_rows].any?
        end

        def title_row_height(item)
          item[:compact_title_rows] ? MULTILINE_TITLE_ROW_HEIGHT : ROW_HEIGHT
        end

        def floating_generic_text(item, horizontal, vertical, width)
          generic = item[:floating_generic]
          return unless generic

          scaled_width = measured_width(generic) * 0.85
          scene_text(generic, horizontal + width - scaled_width + 4.0,
                     vertical + (font_size * 0.9), "kind", "start")
        end

        def title_role(item, index)
          header = item[:title_rows].size - item[:name_rows]
          index < header ? "kind" : "class_name"
        end

        def member_contents(item, horizontal, cursor, width)
          return [[], []] if item[:member_rows].empty?

          rows = member_row_geometry(item, cursor)
          [member_texts(item, horizontal, width, rows[:baselines]),
           member_lines(item, horizontal, width, rows)]
        end

        def member_lines(item, horizontal, width, rows)
          base = rows[:baselines]
          [segment(horizontal, rows[:head], horizontal + width, rows[:head]),
           *group_rules(item, horizontal, width, base),
           *underlines(item, horizontal, base),
           *rules(item, horizontal, width, base)]
        end

        # Baselines of the member rows and the y of the rule above them. The
        # default box stacks rows from the title; a compact box, whose height
        # was sized from the reference row pitch, stacks them up from its
        # bottom edge so the last row always lies inside it.
        def member_row_geometry(item, cursor)
          return compact_row_geometry(item) if item[:compact_members]

          { head: cursor - (ROW_HEIGHT / 2),
            baselines: item[:member_rows].each_index.map do |index|
              cursor + 6.0 + (index * ROW_HEIGHT)
            end }
        end

        def compact_row_geometry(item)
          offsets = compact_row_offsets(item)
          last = item.fetch(:compact_bottom) - COMPACT_BOTTOM_PAD -
            empty_gap(item, :tail)
          baselines = offsets.map { |offset| last - offsets.last + offset }
          { head: baselines.first - COMPACT_HEAD_GAP - offsets.first,
            baselines: baselines }
        end

        # `:lead` or `:tail`: the gap an empty field or method group keeps.
        def empty_gap(item, side)
          return 0.0 unless item[:empty_gaps]

          MemberPitch.public_send(side, item[:member_kinds])
        end

        def compact_row_offsets(item)
          MemberPitch.layout(item[:member_kinds], item[:member_rows],
                             gaps: item[:empty_gaps]).first
        end

        # A thin rule between the field group and the method group, and one
        # closing whichever of them is empty.
        def group_rules(item, horizontal, width, baselines)
          return [] unless item[:compact_members]

          group_rule_heights(item, baselines).map do |at|
            segment(horizontal, at, horizontal + width, at)
          end
        end

        def group_rule_heights(item, baselines)
          member_group_boundaries(item[:member_kinds]).map do |index|
            ((baselines[index - 1] + baselines[index]) / 2.0) - 5.2911
          end + empty_group_rules(item, baselines)
        end

        def empty_group_rules(item, baselines)
          [(baselines.first - COMPACT_HEAD_GAP if
              empty_gap(item, :lead).positive?),
           (baselines.last + COMPACT_BOTTOM_PAD if
              empty_gap(item, :tail).positive?)].compact
        end

        def member_texts(item, horizontal, width, baselines)
          insets = member_insets(item)
          item[:member_rows].each_with_index.filter_map do |content, index|
            next if content.empty?

            text = member_text_row(visible_member(item, content, index),
                                   item[:member_modifiers][index],
                                   [horizontal, width, insets[index]],
                                   baselines.fetch(index))
            text.icon = member_icon(item, index, horizontal, baselines)
            text
          end
        end

        def member_icon(item, index, horizontal, baselines)
          return unless item[:icons_enabled]

          MemberIcon.at(item[:member_visibilities][index],
                        item[:member_kinds][index], horizontal,
                        baselines.fetch(index))
        end

        def member_insets(item)
          MemberIcon.insets(item[:member_kinds], item[:member_visibilities],
                            item[:icons_enabled])
        end

        def visible_member(item, content, index)
          MemberIcon.visible_text(content, item[:member_visibilities][index],
                                  item[:icons_enabled])
        end

        # A separator's title is centred; any other row starts at its inset.
        def member_text_row(content, modifiers, box, vertical)
          left, width, inset = box
          if modifiers.include?(:rule)
            return scene_text(content, left + (width / 2.0), vertical,
                              "member", "middle")
          end

          role = modifiers.include?(:abstract) ? "member_abstract" : "member"
          scene_text(content, left + inset, vertical, role, "start")
        end

        # A separator is a rule across the box, broken around its title.
        def rules(item, horizontal, width, baselines)
          item[:member_rows].each_with_index.flat_map do |content, index|
            rule, character = item[:member_modifiers][index]
            next [] unless rule == :rule

            MemberRule.style(character,
                             rule_segments(content, horizontal,
                                           baselines.fetch(index) - 4.0, width))
          end
        end

        def rule_segments(content, horizontal, vertical, width)
          right = horizontal + width
          if content.empty?
            return [segment(horizontal, vertical, right,
                            vertical)]
          end

          gap = standard_text_width(content, font_size) / 2.0
          middle = horizontal + (width / 2.0)
          [segment(horizontal, vertical, middle - gap, vertical),
           segment(middle + gap, vertical, right, vertical)]
        end

        # A static member is underlined, as PlantUML draws it.
        def underlines(item, horizontal, baselines)
          item[:member_rows].each_with_index.filter_map do |content, index|
            next unless item[:member_modifiers][index].include?(:static)

            underline(item, horizontal, content, [index, baselines])
          end
        end

        def underline(item, horizontal, content, (index, baselines))
          vertical = baselines.fetch(index) + 2.0
          left = horizontal + member_insets(item).fetch(index)
          width = standard_text_width(visible_member(item, content, index),
                                      font_size)
          segment(left, vertical, left + width, vertical)
        end

        def build_relations(diagram, boxes, nodes)
          by_name = boxes.to_h { |box| [box.id.delete_prefix("package-"), box] }
          owners = junction_owners(diagram)
          engine = RankChain.engine(diagram)
          context = { by_name: by_name, owners: owners, nodes: nodes,
                      engine: engine }
          scenes = diagram.relations.each_with_index.flat_map do |rel, index|
            next [] if rel.layout_only?

            relation_scenes(rel, index, context)
          end
          separate_relation_labels(scenes)
        end

        def separate_relation_labels(scenes)
          RelationLabelSeparator.new(
            size: font_size * SMALL_TEXT_SCALE,
            width_of: method(:end_text_width),
            drawn_width_of: lambda { |content|
              Drawing::Face.width(content, size: font_size * SMALL_TEXT_SCALE)
            },
          ).call(scenes)
        end

        def relation_scenes(relation, index, context)
          by_name = context.fetch(:by_name)
          ends = relation_ends(relation, by_name)
          end_texts = EndTexts.new(relation, context.fetch(:engine))
          junctions = context.fetch(:owners)[index]
          if junctions.empty?
            return plain_relation_scene(relation, index, ends, end_texts)
          end

          junction_relation_scenes(relation, index,
                                   [ends, end_texts, junctions], context)
        end

        def relation_ends(relation, by_name)
          [relation.left, relation.right].map { |name| by_name.fetch(name) }
        end

        def plain_relation_scene(relation, index, ends, end_texts)
          [relation_scene(relation, "relation-#{index}",
                          relation_endpoints(*ends), end_texts)]
        end

        def junction_relation_scenes(relation, index, details, context)
          ends, end_texts, junctions = details
          by_name = context.fetch(:by_name)
          junction = junction_box(context.fetch(:nodes)[index], ends,
                                  context.fetch(:engine))
          entries = junctions.map { |entry| [*entry, by_name] }
          junction_scenes(relation, index, [ends, junction, end_texts], entries)
        end

        # The association classes, with their numbers, grouped by the index
        # of the first relation joining their pair, written either way round.
        def junction_owners(diagram)
          owners = Hash.new { |hash, index| hash[index] = [] }
          diagram.junctions.each_with_index do |junction, number|
            index = junction_relation_index(diagram.relations, junction)
            owners[index] << [junction, number]
          end
          owners
        end

        def junction_relation_index(relations, junction)
          pair = [junction.from, junction.to].sort
          relations.index do |relation|
            [relation.left, relation.right].sort == pair
          end
        end

        # The junction node, or a zero-size one at the middle of the
        # relation when the grid placed the classes.
        def junction_box(node, ends, engine)
          node ||= [*midpoint(*relation_endpoints(*ends).values_at(:left,
                                                                   :right)),
                    0.0, 0.0]
          x, y, width, height = node
          # Smetana's legs stop at the junction node's edge; the default
          # engine runs one line through its middle.
          return junction_node(x, y, width, height) unless engine == :dot

          Scene::Box.new(id: "junction", x: x + (width / 2),
                         y: y + (height / 2), width: 0.0, height: 0.0,
                         texts: [], separators: [], kind: "junction")
        end

        def relation_scene(relation, id, endpoints, end_texts, style = {})
          sides = style.fetch(:sides, %i[left right])
          boxes, endpoints = qualifier_boxes(relation, end_texts, endpoints,
                                             sides)
          texts = relation_texts(relation, endpoints, end_texts, sides,
                                 boxes.size)
          drawn = styled_markers(relation, style, sides, endpoints)
          relation_record(relation, id, texts: texts, markers: drawn,
                                        qualifiers: boxes,
                                        path: relation_path_for(relation,
                                                                endpoints))
        end

        def styled_markers(relation, style, sides, endpoints)
          relation_markers(relation, style.fetch(:markers, relation.markers),
                           sides, endpoints)
        end

        def relation_record(relation, id, **drawn)
          Scene::Relation.new(id: id, dashed: relation.dashed?,
                              dotted: relation.dotted?,
                              stroke: svg_colour(relation.color),
                              stroke_width: relation.width, **drawn)
        end

        # A one-line bracketed qualifier is a box on the class edge, and the
        # link starts at the box's far side.
        # @return [Array(Array<Scene::Box>, Hash)] the boxes and the
        #   endpoints moved clear of them
        def qualifier_boxes(relation, end_texts, endpoints, sides)
          first, second = end_texts.sides
          direction = unit_vector(*endpoints.values_at(first, second))
          entries = qualifier_entries(end_texts, endpoints, sides, relation)
          placed = entries.to_h do |entry|
            [entry[:side], qualifier_placement(entry, endpoints, direction,
                                               first)]
          end
          [placed.values.map(&:box),
           endpoints.merge(placed) { |_, tip, found| found.clear(tip) }]
        end

        # Only on a straight vertical, unlabelled link: a slanted or flat one
        # is drawn between estimated class positions and beside labels that
        # sit away from the reference's, so a box would land off it.
        def qualifier_entries(end_texts, endpoints, sides, relation)
          return [] unless boxable_link?(endpoints, relation)

          end_texts.entries.select do |entry|
            entry[:kind] == :qualifier && entry[:pieces].one? &&
              sides.include?(entry[:side])
          end
        end

        def boxable_link?(endpoints, relation)
          left, right = endpoints.values_at(:left, :right)
          !endpoints[:control] && !relation.label &&
            (left[0] - right[0]).abs < AXIS_TOLERANCE
        end

        def qualifier_placement(entry, endpoints, direction, first)
          content = entry[:pieces].first
          outward = entry[:side] == first ? direction : direction.map(&:-@)
          width = measure_text(content, font_size: font_size)[:width]
          QualifierBox.place(content, endpoints.fetch(entry[:side]), outward,
                             width, font_size)
        end

        # A bracketed colour is a CSS name (`red`) or bare hex digits.
        def svg_colour(color)
          return unless color

          color.match?(/\A(?:\h{3}|\h{6}|\h{8})\z/) ? "##{color}" : color
        end

        def relation_markers(relation, markers, sides, endpoints)
          half_width = qualified_marker_half_width(relation, endpoints)
          drawn_markers = marker_scenes(markers.slice(*sides), endpoints,
                                        half_width: half_width)
          drawn_markers << label_arrow_scene(relation, endpoints)
          scale_thick_markers(drawn_markers.compact, relation, endpoints)
        end

        # PlantUML grows an arrowhead with the line it ends: a head on a
        # line thicker than 4 is as many times larger as 4 goes into it.
        def scale_thick_markers(markers, relation, endpoints)
          factor = relation.width.to_f / THICK_LINE
          return markers unless factor > 1.0

          markers.each do |marker|
            next unless marker.shape == "polygon"

            tip = marker_tip(marker, endpoints)
            marker.points = scaled_points(marker.points, tip, factor)
          end
        end

        def marker_tip(marker, endpoints)
          first = point_pairs(marker.points).first
          endpoints.values_at(:left, :right).compact.min_by do |tip|
            JsMath.hypot(*tip.zip(first).map { |at, from| at - from })
          end
        end

        def scaled_points(points, tip, factor)
          formatted_points(point_pairs(points).map do |point|
            point.zip(tip).map { |at, from| from + ((at - from) * factor) }
          end)
        end

        def point_pairs(points)
          points.split.map { |pair| pair.split(",").map(&:to_f) }
        end

        def relation_path_for(relation, endpoints)
          ordered = if reversed_qualified?(relation)
                      endpoints.merge(left: endpoints[:right],
                                      right: endpoints[:left])
                    else
                      endpoints
                    end
          qualified_special_path(relation, ordered) ||
            controlled_relation_path(relation, ordered)
        end

        def qualified_special_path(relation, ordered)
          if fan_qualifier_relation?(relation)
            fan_qualifier_path(relation, ordered)
          elsif long_qualified_vertical?(relation, ordered)
            long_qualified_vertical_path(ordered)
          end
        end

        def controlled_relation_path(relation, ordered)
          control = qualified_label_control(relation, ordered) ||
            qualified_lane_control(relation, ordered)
          return styled_curve_path(relation, ordered) unless control

          "M #{point(ordered[:left])} Q #{point(control)} " \
            "#{point(ordered[:right])}"
        end

        def styled_curve_path(relation, ordered)
          first, last = ordered.values_at(:left, :right)
          controls = StyledRelationCurve.controls(relation, first, last)
          return relation_path(ordered) unless controls

          "M #{point(first)} C #{point(controls.first)} " \
            "#{point(controls.last)} #{point(last)}"
        end

        def fan_qualifier_relation?(relation)
          multiplicities = [relation.left_multiplicity,
                            relation.right_multiplicity].compact
          relation.direction.nil? && relation.length == 2 &&
            multiplicities.one? && multiplicities.first.start_with?("[")
        end

        def fan_qualifier_path(relation, endpoints)
          first, last = endpoints.values_at(:left, :right)
          width = standard_text_width(fan_qualifier_text(relation), font_size) +
            QUALIFIED_FAN_LANE_ALLOWANCE
          left, right = fan_lane_points(first, last, width)
          "M #{point(first)} L #{point(left)} L #{point(right)} " \
            "L #{point(last)}"
        end

        def fan_qualifier_text(relation)
          [relation.left_multiplicity, relation.right_multiplicity]
            .compact.first.delete_prefix("[").delete_suffix("]")
        end

        def fan_lane_points(first, last, width)
          centre = midpoint(first, last).first
          rise = (last[1] - first[1]) / 3
          [offset_point([centre, first[1]], -(width / 2), rise),
           offset_point([centre, last[1]], width / 2, -rise)]
        end

        def long_qualified_vertical?(relation, endpoints)
          qualifier_relation?(relation) && relation.length > 2 &&
            steep?(*endpoints.values_at(:left, :right))
        end

        def long_qualified_vertical_path(endpoints)
          first, last = endpoints.values_at(:left, :right)
          vertical = (last[1] - first[1]) / 3
          outgoing = offset_point(first, -QUALIFIED_LONG_CURVE_OFFSET, vertical)
          incoming = offset_point(last, QUALIFIED_LONG_CURVE_OFFSET, -vertical)
          "M #{point(first)} C #{point(outgoing)} #{point(incoming)} " \
            "#{point(last)}"
        end

        def offset_point(origin, delta_x, delta_y)
          [origin[0] + delta_x, origin[1] + delta_y]
        end

        def qualified_lane_control(relation, endpoints)
          return unless single_qualifier_with_other_end?(relation)

          left, right = endpoints.values_at(:left, :right)
          return if steep?(left, right)

          middle = midpoint(left, right)
          outward = if middle[1] < @qualified_route_middle
                      -QUALIFIED_FLAT_CURVE_OFFSET
                    else
                      QUALIFIED_FLAT_CURVE_OFFSET
                    end
          [middle[0], middle[1] + outward]
        end

        def single_qualifier_with_other_end?(relation)
          multiplicities = [relation.left_multiplicity,
                            relation.right_multiplicity].compact
          multiplicities.one? { |text| text.start_with?("[") } &&
            multiplicities.size > 1
        end

        def reversed_qualified?(relation)
          qualifiers = [relation.left_multiplicity,
                        relation.right_multiplicity]
          qualifiers.compact.any? { |text| text.start_with?("[") } &&
            %i[up left].include?(relation.direction)
        end

        def qualified_label_control(relation, endpoints)
          return unless qualifier_relation?(relation) && label_arrow?(relation)

          left, right = endpoints.values_at(:left, :right)
          return if steep?(left, right)

          middle = midpoint(left, right)
          outward = middle[1] < @qualified_route_middle ? -30.0 : 30.0
          [middle[0], middle[1] + outward]
        end

        def qualifier_relation?(relation)
          [relation.left_multiplicity, relation.right_multiplicity]
            .compact.any? { |text| text.start_with?("[") }
        end

        def qualified_marker_half_width(relation, endpoints)
          qualifiers = [relation.left_multiplicity,
                        relation.right_multiplicity]
          if qualifiers.all? { |text| text&.start_with?("[") }
            QUALIFIED_DOUBLE_END_HALF_WIDTH
          else
            inheritance_marker_half_width(relation, endpoints, qualifiers)
          end
        end

        def inheritance_marker_half_width(relation, endpoints, qualifiers)
          return unless @qualified_layout_active && qualifiers.compact.empty?
          return unless relation.markers.value?(:implementation)

          left, right = endpoints.values_at(:left, :right)
          QUALIFIED_INHERITANCE_HALF_WIDTH if steep?(left, right)
        end

        def label_arrow?(relation)
          relation.label&.match?(/[ \t]+[<>]\z/)
        end

        def label_arrow_scene(relation, endpoints)
          return unless qualifier_relation?(relation) && label_arrow?(relation)

          centre, direction = label_arrow_geometry(relation, endpoints)
          tip = shift(centre, *direction, 5.0)
          base = shift(centre, *direction, -4.0)
          points = [tip, marker_side(base, direction, 3.0),
                    marker_side(base, direction, -3.0)]
          Scene::Marker.new(shape: "polygon", filled: true,
                            points: formatted_points(points))
        end

        def label_arrow_geometry(relation, endpoints)
          left, right = endpoints.values_at(:left, :right)
          direction = unit_vector(left, right)
          direction = direction.map(&:-@) if relation.label.end_with?("<")
          centre = qualified_label_control(relation, endpoints) ||
            midpoint(left, right)
          if steep?(left, right)
            centre = shift(centre, 1.0, 0.0,
                           QUALIFIED_STEEP_ARROW_OFFSET)
          end
          [centre, direction]
        end

        # PlantUML turns a relation carrying an association class into two
        # legs meeting at a junction node, each keeping its own end's text,
        # plus a dashed link from that node to each association class. An
        # `up` or `left` word moves each end's marker to the other leg, as
        # the pinned references draw it.
        def junction_scenes(relation, index, boxes, owners)
          (from, to), junction, end_texts = boxes
          legs = junction_legs(relation, index, [from, junction, to],
                               end_texts)
          legs.first.markers << junction_dot(junction)
          [*legs, *owners.map { |entry| owner_link(junction, *entry) }]
        end

        def junction_legs(relation, index, (from, junction, to), end_texts)
          swap = %i[up left].include?(relation.direction)
          [[:left, "from", from, junction],
           [:right, "to", junction, to]].map do |side, name, tail, head|
            markers = junction_markers(relation.markers, swap, side)
            relation_scene(relation, "relation-#{index}-#{name}",
                           relation_endpoints(tail, head), end_texts,
                           sides: [side], markers: markers)
          end
        end

        def junction_node(left, top, width, height)
          Scene::Box.new(id: "junction", x: left, y: top, width: width,
                         height: height, texts: [], separators: [],
                         kind: "junction")
        end

        # The filled dot where an association class meets its relation.
        def junction_dot(junction)
          Scene::Marker.new(shape: "dot", filled: true,
                            cx: junction.x + (junction.width / 2),
                            cy: junction.y + (junction.height / 2),
                            r: JUNCTION_DOT_RADIUS)
        end

        def junction_markers(markers, swap, side)
          opposite = side == :left ? :right : :left
          { side => markers[swap ? opposite : side] }
        end

        def owner_link(junction, owner, number, by_name)
          edge = relation_endpoints(junction, by_name.fetch(owner.owner))
          Scene::Relation.new(id: "junction-#{number}", dashed: true,
                              path: relation_path(edge), texts: [], markers: [])
        end

        def midpoint(first, second)
          [(first[0] + second[0]) / 2, (first[1] + second[1]) / 2]
        end

        def relation_endpoints(left_box, right_box)
          return self_relation_endpoints(left_box) if left_box.equal?(right_box)

          aligned = aligned_package_endpoints(left_box, right_box)
          return aligned if aligned

          {
            left: boundary_point(left_box, right_box),
            right: boundary_point(right_box, left_box),
          }
        end

        def aligned_package_endpoints(left_box, right_box)
          if package_frame?(left_box)
            vertical_package_endpoints(left_box, right_box, :left)
          elsif package_frame?(right_box)
            vertical_package_endpoints(right_box, left_box, :right)
          end
        end

        def package_frame?(box)
          box.id.start_with?("package-")
        end

        def vertical_package_endpoints(frame, box, frame_side)
          centre = box_centre(box)
          return unless centre.first.between?(frame.x, frame.x + frame.width)

          points = vertical_package_points(frame, box, centre.first)
          return unless points

          frame_point, box_point = points
          return { left: frame_point, right: box_point } if frame_side == :left

          { left: box_point, right: frame_point }
        end

        def vertical_package_points(frame, box, horizontal)
          verticals = vertical_package_edges(frame, box)
          verticals&.map { |vertical| [horizontal, vertical] }
        end

        def vertical_package_edges(frame, box)
          return [bottom_of(frame), box.y] if below?(box, frame)

          [frame.y, bottom_of(box)] if below?(frame, box)
        end

        def below?(box, other)
          box.y >= bottom_of(other)
        end

        def bottom_of(box)
          box.y + box.height
        end

        def self_relation_endpoints(box)
          endpoints = { left: right_edge_point(box,
                                               SELF_RELATION_START_RATIO) }
          endpoints[:right] = right_edge_point(box, SELF_RELATION_END_RATIO)
          endpoints[:control] = right_edge_point(
            box, 0.5, offset: SELF_RELATION_CONTROL_OFFSET
          )
          endpoints
        end

        def right_edge_point(box, height_ratio, offset: 0.0)
          [box.x + box.width + offset, box.y + (box.height * height_ratio)]
        end

        def boundary_point(box, target)
          boundary_toward(box, box_centre(target))
        end

        def boundary_toward(box, destination)
          centre = box_centre(box)
          delta = vector_between(centre, destination)
          shift(centre, *delta, boundary_scale(box, delta))
        end

        def vector_between(from, to)
          [to[0] - from[0], to[1] - from[1]]
        end

        def boundary_scale(box, delta)
          horizontal = axis_scale(box.width, delta[0])
          vertical = axis_scale(box.height, delta[1])
          [horizontal, vertical].compact.min
        end

        def axis_scale(size, delta)
          return if delta.zero?

          (size / 2) / delta.abs
        end

        def box_centre(box)
          [box.x + (box.width / 2), box.y + (box.height / 2)]
        end

        def relation_path(endpoints)
          left = endpoints.fetch(:left)
          right = endpoints.fetch(:right)
          return "M #{point(left)} L #{point(right)}" unless endpoints[:control]

          control = endpoints.fetch(:control)
          "M #{point(left)} Q #{point(control)} #{point(right)}"
        end

        def marker_scenes(markers, endpoints, half_width: nil)
          markers.compact.map do |side, kind|
            tip = endpoints.fetch(side)
            opposite = side == :left ? :right : :left
            other = endpoints[:control] || endpoints.fetch(opposite)
            marker_scene(kind, tip, other, half_width: half_width)
          end
        end

        def marker_scene(kind, tip, other, half_width: nil)
          return nesting_scene(tip, other) if kind == :nesting

          Scene::Marker.new(
            shape: "polygon", filled: FILLED_MARKERS.include?(kind),
            points: marker_points(tip, other, marker_shape(kind),
                                  half_width: half_width)
          )
        end

        def nesting_scene(tip, other)
          centre = shift(tip, *unit_vector(tip, other), NESTING_RADIUS)
          Scene::Marker.new(shape: "nesting", filled: false, cx: centre[0],
                            cy: centre[1], r: NESTING_RADIUS,
                            cross: cross_path(centre))
        end

        def cross_path(centre)
          x, y = centre
          reach = NESTING_RADIUS
          "M #{x - reach} #{y} L #{x + reach} #{y} " \
            "M #{x} #{y - reach} L #{x} #{y + reach}"
        end

        def marker_shape(relation_kind)
          return :diamond if %i[aggregation composition].include?(relation_kind)
          return :arrow if ARROW_MARKERS.include?(relation_kind)

          :triangle
        end

        def marker_points(tip, other, shape, half_width: nil)
          direction = unit_vector(other, tip)
          return arrow_points(tip, direction, half_width) if shape == :arrow
          return diamond_points(tip, direction, half_width) if shape == :diamond

          base = shift(tip, *direction, -MARKER_LENGTH)
          half_width ||= MARKER_HALF_WIDTH
          formatted_points(
            [tip, marker_side(base, direction, half_width),
             marker_side(base, direction, -half_width)],
          )
        end

        # PlantUML's aggregation and composition diamond.
        def diamond_points(tip, direction, half_width = nil)
          middle = shift(tip, *direction, -(DIAMOND_LENGTH / 2))
          half_width ||= DIAMOND_HALF_WIDTH
          formatted_points(
            [tip, marker_side(middle, direction, half_width),
             shift(tip, *direction, -DIAMOND_LENGTH),
             marker_side(middle, direction, -half_width)],
          )
        end

        # PlantUML's open arrowhead: two wings joined through a notch.
        def arrow_points(tip, direction, half_width = nil)
          base = shift(tip, *direction, -ARROW_LENGTH)
          half_width ||= ARROW_HALF_WIDTH
          formatted_points(
            [tip, marker_side(base, direction, half_width),
             shift(tip, *direction, -ARROW_NOTCH),
             marker_side(base, direction, -half_width)],
          )
        end

        def marker_side(base, direction, distance)
          shift(base, -direction[1], direction[0], distance)
        end

        def formatted_points(points)
          points.map do |coordinate|
            point(coordinate, separator: ",")
          end.join(" ")
        end

        def unit_vector(from, to)
          delta_horizontal, delta_vertical = vector_between(from, to)
          length = JsMath.hypot(delta_horizontal, delta_vertical)
          return [1.0, 0.0] if length.zero?

          [delta_horizontal / length, delta_vertical / length]
        end

        def shift(origin, direction_horizontal, direction_vertical, distance)
          [origin[0] + (direction_horizontal * distance),
           origin[1] + (direction_vertical * distance)]
        end

        # The label rides with the left end, so a relation split into legs
        # still shows it once.
        def relation_texts(relation, endpoints, end_texts, sides, boxed = 0)
          first, second = end_texts.sides
          direction = unit_vector(*endpoints.values_at(first, second))
          label = relation_text_label(relation, endpoints, sides)
          texts = positioned_end_texts(unboxed_entries(end_texts, boxed),
                                       endpoints, direction, first, sides)
          [label, *texts].compact
        end

        def relation_text_label(relation, endpoints, sides)
          return unless sides.include?(:left)

          content = visible_relation_label(relation.label)
          clearance = [relation.width.to_f - 1.0, 0.0].max / 2
          curved_relation_label(content, relation, endpoints, clearance) ||
            relation_label(content, endpoints, clearance)
        end

        # A label on a sloping curve starts, or ends, on the side where the
        # curve runs away below it, so the curve does not cross the text.
        def curved_relation_label(content, relation, endpoints, clearance)
          left, right = endpoints.values_at(:left, :right)
          point = StyledRelationCurve.label_point(relation, left, right)
          return unless content && point && !endpoints[:control]

          descending = descending?(left, right)
          scene_text(content, point[0] + (descending ? LABEL_GAP : -LABEL_GAP),
                     point[1] - LABEL_OFFSET - clearance, "relation_label",
                     descending ? "start" : "end")
        end

        def descending?(left, right)
          horizontal, vertical = vector_between(left, right)
          (horizontal * vertical).positive?
        end

        def visible_relation_label(label)
          label&.sub(/[ \t]+[<>]\z/, "")
        end

        def unboxed_entries(end_texts, boxed)
          return end_texts.entries if boxed.zero?

          end_texts.entries.reject do |entry|
            entry[:kind] == :qualifier && entry[:pieces].one?
          end
        end

        def positioned_end_texts(entries, endpoints, direction, first, sides)
          selected = entries.select { |entry| sides.include?(entry[:side]) }
          selected.flat_map do |entry|
            inward = entry[:side] == first ? 1 : -1
            endpoint = endpoints.fetch(entry[:side])
            end_text(entry, endpoint, direction, inward)
          end
        end

        # Above the middle of a flat line; beside a steep one, centred on
        # its middle, as PlantUML draws a label in its own rank.
        def relation_label(content, endpoints, clearance = 0.0)
          return unless content

          return self_relation_label(content, endpoints) if endpoints[:control]

          left, right = endpoints.values_at(:left, :right)
          if beside_label?(left, right)
            return steep_label_for(content, left, right, clearance)
          end

          scene_text(content, midpoint(left, right).first,
                     flat_label_baseline(content, left, right, clearance),
                     "relation_label", "middle")
        end

        def steep_label_for(content, left, right, clearance)
          horizontal, middle = midpoint(left, right)
          steep_relation_label(content, horizontal, middle,
                               [left, right], clearance)
        end

        # Above the line; higher where a slope climbs under the text's
        # ends, so the line does not run through it.
        def flat_label_baseline(content, left, right, clearance)
          centre, middle = midpoint(left, right)
          size = font_size * SMALL_TEXT_SCALE
          half = standard_text_width(content.to_s, size) / 2
          top = LabelClearance.top_between(left, right, centre - half,
                                           centre + half)
          [middle - LABEL_OFFSET, top - (size * TEXT_DESCENT)].min - clearance
        end

        def self_relation_label(content, endpoints)
          horizontal = self_relation_label_horizontal(endpoints)
          baseline = self_relation_label_baseline(endpoints)
          scene_text(content, horizontal, baseline,
                     "relation_label", "start")
        end

        def self_relation_label_horizontal(endpoints)
          left, right, control = endpoints.values_at(:left, :right, :control)
          curve_right = (left[0] + (2 * control[0]) + right[0]) / 4
          curve_right + SELF_RELATION_LABEL_GAP
        end

        def self_relation_label_baseline(endpoints)
          left, right = endpoints.values_at(:left, :right)
          vertical = midpoint(left, right).last
          size = font_size * SMALL_TEXT_SCALE
          vertical + (size * (1 - TEXT_DESCENT) / 2)
        end

        def steep?(left, right)
          horizontal, vertical = vector_between(left, right)
          vertical.abs > horizontal.abs
        end

        # A line this near the diagonal would run through a label centred
        # above its middle, so the label goes beside it.
        def beside_label?(left, right)
          horizontal, vertical = vector_between(left, right)
          vertical.abs > horizontal.abs * BESIDE_LABEL_SLOPE
        end

        def steep_relation_label(content, horizontal, middle, line, clearance)
          size = font_size * SMALL_TEXT_SCALE
          baseline = middle + (size * (1 - TEXT_DESCENT) / 2)
          reach = LabelClearance.right_between(*line, baseline - size,
                                               baseline)
          scene_text(content, [horizontal, reach].max + clearance + LABEL_GAP,
                     baseline,
                     "relation_label", "start")
        end

        # A multiplicity sits on the right of the line as it runs from the
        # link's first class to its second, and a role on its left. Each
        # text hugs its end, as PlantUML draws it: beside a steep line it
        # grows away from the line and into the gap along it, beside a flat
        # one into the gap and away from the line. `inward` is 1 at the
        # first end and -1 at the second.
        def end_text(entry, endpoint, direction, inward)
          point, sideways, upright = end_text_position(entry, endpoint,
                                                       direction, inward)
          anchor = sideways[0].positive? ? "start" : "end"
          if entry[:multiline]
            return multiline_end_text_run(entry[:pieces],
                                          hug(point, upright[1]), anchor)
          end

          end_text_run(entry[:pieces], hug(point, upright[1]), anchor)
        end

        def end_text_position(entry, endpoint, direction, inward)
          normal, along = end_text_vectors(entry, direction, inward)
          point = shift(shift(endpoint, *along, END_TEXT_ALONG),
                        *normal, END_TEXT_ACROSS)
          sideways, upright = if direction[1].abs >= direction[0].abs
                                [normal, along]
                              else
                                [along, normal]
                              end
          [point, sideways, upright]
        end

        def end_text_vectors(entry, direction, inward)
          side = entry[:kind] == :role ? -1 : 1
          normal = [-direction[1] * side, direction[0] * side]
          inward *= -1 if entry[:kind] == :qualifier
          along = direction.map { |component| component * inward }
          [normal, along]
        end

        # The baseline that puts the text just below `point`, or just above.
        def hug(point, downward)
          size = font_size * SMALL_TEXT_SCALE
          drop = downward.positive? ? size : -(size * TEXT_DESCENT)
          [point[0], point[1] + drop]
        end

        # A numbered item's `1.` and its text are drawn side by side, one
        # space apart, as one run.
        def end_text_run(pieces, point, anchor)
          if pieces.one?
            return [scene_text(pieces.first, *point, "multiplicity", anchor)]
          end

          numbered_end_text_run(pieces, point, anchor)
        end

        def multiline_end_text_run(lines, point, anchor)
          line_height = font_size * SMALL_TEXT_SCALE * 1.215
          top = point[1] - (line_height * (lines.size - 1))
          lines.each_with_index.map do |line, index|
            scene_text(line, point[0], top + (index * line_height),
                       "multiplicity", anchor)
          end
        end

        def numbered_end_text_run(pieces, point, anchor)
          width = end_text_width(pieces.join(" "))
          start = point[0] - anchor_offset(anchor, width)
          offset = end_text_width("#{pieces.first} ")
          baseline = point[1]
          [scene_text(pieces.first, start, baseline, "multiplicity", "start"),
           scene_text(pieces.last, start + offset, baseline, "multiplicity",
                      "start")]
        end

        def anchor_offset(anchor, width)
          { "end" => width, "middle" => width / 2 }.fetch(anchor, 0)
        end

        def end_text_width(content)
          measure_text(content, font_size: font_size * SMALL_TEXT_SCALE)[:width]
        end

        def label_widths(diagram)
          diagram.relations.each_with_index.filter_map do |relation, index|
            label = visible_relation_label(relation.label)
            [index, end_text_width(label)] if label
          end.to_h
        end

        def scene_text(content, horizontal, vertical, role, anchor)
          Scene::Text.new(content: content, x: horizontal, y: vertical,
                          role: role,
                          anchor: anchor)
        end

        def segment(from_horizontal, from_vertical,
                    to_horizontal, to_vertical)
          Scene::Segment.new(
            x1: from_horizontal, y1: from_vertical,
            x2: to_horizontal, y2: to_vertical
          )
        end

        def point(coordinates, separator: " ")
          coordinates.map { |number| number.round(3) }.join(separator)
        end

        def canvas_width(boxes, _box_width)
          boxes.map { |box| box.x + box.width }.max + boxes.map(&:x).min
        end

        def widest_box(specifications)
          widths = specifications.map { |item| item[:width] }
          widths.max
        end

        def box_rows(boxes)
          boxes.group_by(&:y).values
        end

        def canvas_height(rows)
          rows.sum { |row| row.map(&:height).max } +
            ((rows.size - 1) * ROW_GAP) + (MARGIN * 2)
        end
      end
    end
  end
end
