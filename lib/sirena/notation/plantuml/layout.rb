# frozen_string_literal: true

require_relative "../../layout/base"
require_relative "caption_layout"
require_relative "class_name"
require_relative "end_texts"
require_relative "ir_reader"
require_relative "package_frames"
require_relative "qualified_association_layout"
require_relative "rank_chain"
require_relative "scene"
require_relative "sequence/text_advances"

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
        MARKER_LENGTH = 12.0
        MARKER_HALF_WIDTH = 7.0
        LABEL_OFFSET = 10.0
        LABEL_GAP = 2.0
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
        MEMBER_NOTE_CLASS_HEIGHT = 48.0
        MEMBER_NOTE_SIDE_PADDING = 6.0
        STANDARD_MEMBER_SIDE_ALLOWANCE = 20.0
        STANDARD_STEREOTYPE_ROW_HEIGHT = 8.62109375
        STANDARD_TITLE_SIDE_ALLOWANCE = 32.0
        # PlantUML removes the otherwise empty member compartment below a
        # one-line title when `hide empty members` is active. Its Smetana
        # boxes also keep four more pixels of side padding than our ordinary
        # measured class box; both values are pinned by the group2712 family.
        EMPTY_MEMBER_COMPARTMENT = 14.0
        EMPTY_CLASS_WIDTH_EXTRA = 8.0
        EMPTY_CLASS_MIN_WIDTH = 41.5
        ARROW_LENGTH = 9.0
        ARROW_HALF_WIDTH = 4.0
        ARROW_NOTCH = 5.0
        DIAMOND_LENGTH = 12.0
        DIAMOND_HALF_WIDTH = 4.0
        ARROW_MARKERS = %i[association dependency].freeze
        FILLED_MARKERS = %i[association dependency composition].freeze
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
                         :STANDARD_MEMBER_SIDE_ALLOWANCE,
                         :STANDARD_STEREOTYPE_ROW_HEIGHT,
                         :STANDARD_TITLE_SIDE_ALLOWANCE,
                         :EMPTY_MEMBER_COMPARTMENT, :EMPTY_CLASS_WIDTH_EXTRA,
                         :EMPTY_CLASS_MIN_WIDTH

        # @param graph [IR::Graph] from {IRAdapter}
        def scene(graph)
          diagram = IRReader.call(graph)
          body = if member_note_family?(diagram)
                   member_note_scene(diagram)
                 else
                   standard_scene(diagram)
                 end
          dress(diagram, body)
        end

        private

        def standard_scene(diagram)
          specifications = box_specifications(diagram)
          qualified = qualified_scene(diagram, specifications)
          return qualified if qualified

          standard_box_scene(diagram, specifications)
        end

        def standard_box_scene(diagram, specifications)
          box_width = widest_box(specifications)
          chain = RankChain.for(diagram)
          return chain_scene(diagram, chain, specifications) if chain

          boxes = position_boxes(rows_by_package(specifications, diagram),
                                 box_width, stable_centers?(diagram),
                                 intrinsic_box_widths?(diagram))

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
          sizes = qualified_sizes(specifications)
          corners = qualified.place(sizes, [MARGIN, MARGIN])
          boxes = chain_boxes(specifications, corners, sizes)
          width, height = chain_dimensions(boxes)
          @qualified_route_middle = qualified_route_middle(boxes)
          Scene.new(width: width, height: height, boxes: boxes, frames: [],
                    relations: scene_relations(diagram, boxes))
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
          Scene.new(width: far_edge(boxes) { |box| box.x + box.width },
                    height: far_edge(boxes) { |box| box.y + box.height },
                    boxes: boxes, relations: [], frames: [])
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
          captions = CaptionLayout.new(diagram, normal_size: font_size,
                                                measure: measure)
          captions.dress(scene)
        end

        def build_scene(diagram, boxes, box_width)
          frames = scene_frames(diagram, boxes)
          Scene.new(width: canvas_width(boxes, box_width),
                    height: scene_height(diagram, boxes), boxes: boxes,
                    relations: scene_relations(diagram, boxes + frames),
                    frames: frames)
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
          build_relations(diagram, boxes, nodes) +
            build_note_links(diagram.notes, boxes)
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
          record = compact_empty_box(record, details[:member_rows], diagram)
          adjust_plain_empty_width(record, klass, diagram, details[:names])
          record = isolated_standard_box(record, klass, diagram, details)
          record.merge(name_rows: details[:names].size,
                       floating_generic: details[:generic],
                       **box_context(klass, diagram))
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

        def adjust_plain_empty_width(specification, klass, diagram, names)
          return unless plain_empty_class?(klass, diagram, names)

          specification[:width] = plain_empty_class_width(names.first)
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

        def plain_empty_class_width(name)
          title_width = Sequence::TextAdvances.width(name,
                                                     font_size: font_size)
          [((title_width * 2).round / 2.0) + 32.0,
           EMPTY_CLASS_MIN_WIDTH].max
        end

        def isolated_standard_box(record, klass, diagram, details)
          return record unless isolated_standard_box?(klass, diagram, details)

          record.merge(
            width: isolated_standard_width(klass, details),
            height: isolated_standard_height(klass, details[:member_rows]),
          )
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
          Sequence::TextAdvances.width(text, font_size: size)
        end

        def isolated_standard_height(klass, member_rows)
          MEMBER_NOTE_CLASS_HEIGHT +
            (member_rows.size * MEMBER_NOTE_ROW_HEIGHT) +
            (header_rows(klass).size * STANDARD_STEREOTYPE_ROW_HEIGHT)
        end

        def box_context(klass, diagram)
          { member_modifiers: klass.body.map(&:modifiers),
            package: klass.package,
            chain: diagram.package_chain(klass.package) }
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
          kind = ["<<#{klass.kind}>>"] unless klass.kind == :class
          tags = klass.stereotypes.map { |tag| "<<#{tag}>>" }
          [*kind, *(tags.join(" ") unless tags.empty?)]
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
          name = member.name.dup
          name += "(#{member.parameters})" if member.parameters
          type = member.type
          content = if type && member.type_position == :prefix
                      "#{type} #{name}"
                    else
                      "#{name}#{": #{type}" if type}"
                    end
          "#{visibility_mark(member.visibility)}#{content}"
        end

        def visibility_mark(visibility)
          { public: "+", private: "-", protected: "#", package: "~" }
            .fetch(visibility, "")
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
          ids = [nil, *diagram.packages.map(&:id)]
          ids.filter_map { |id| by_package[id] }
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
          body = diagram.classes.any? { |klass| klass.body.any? }
          diagram.notes.any? || body ||
            diagram.directives.any? { |line| line.match?(/\A(?:hide|show)\b/i) }
        end

        def position_boxes(rows, box_width, stable_centers, intrinsic_widths)
          tops = row_tops(rows)
          placement = box_placement(rows, box_width, stable_centers,
                                    intrinsic_widths)
          rows.each_with_index.flat_map do |row, row_index|
            position_row(row, tops[row_index], box_width, placement)
          end
        end

        def box_placement(rows, box_width, stable_centers, intrinsic_widths)
          { left: left_margin(rows),
            footprint: box_footprint(box_width, stable_centers),
            box_width: box_width,
            intrinsic_widths: intrinsic_widths }
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
          width = if item && placement[:intrinsic_widths]
                    item.fetch(:width)
                  else
                    placement[:box_width]
                  end

          slot + ((placement[:footprint] - width) / 2)
        end

        def row_tops(rows)
          chains = rows.map { |row| row.compact.first[:chain] || [] }
          first = [MARGIN + frame_space([], chains.first)]
          row_steps(rows, chains).each_with_object(first) do |step, tops|
            tops << (tops.last + step)
          end
        end

        def row_steps(rows, chains)
          row_heights(rows).each_with_index.map do |height, index|
            space = frame_space(chains[index], chains[index + 1] || [])
            height + ROW_GAP + space
          end
        end

        def row_heights(rows)
          rows.map { |row| row.compact.map { |item| item[:height] }.max }
        end

        # The room for the frames closed on leaving the packages `above` and
        # opened on entering the packages `below`, each given outermost first.
        def frame_space(above, below)
          shared = above.zip(below).take_while { |a, b| a == b }.size

          ((above.size - shared) * PackageFrames::CLOSE) +
            ((below.size - shared) * PackageFrames::OPEN)
        end

        def column_count(items)
          items.compact.size > 1 ? 2 : 1
        end

        # Room on the left for the deepest stack of package frames.
        def left_margin(rows)
          items = rows.flat_map(&:compact)
          chains = items.map { |item| item[:chain] }
          depth = chains.compact.map(&:size).max.to_i
          [MARGIN, (depth * PackageFrames::SIDE) + 8.0].max
        end

        def build_box(item, left, top, box_width)
          texts, separators = box_contents(item, left, top, box_width)

          Scene::Box.new(
            id: item[:id], x: left, y: top, width: box_width,
            height: item[:height], texts: texts, separators: separators,
            kind: item[:note] ? "note" : "class", fill: item[:note]&.color
          )
        end

        def note_texts(item, horizontal, vertical)
          item[:rows].each_with_index.map do |content, index|
            baseline = vertical + BOX_PADDING + font_size + (index * ROW_HEIGHT)
            scene_text(content, horizontal + BOX_PADDING, baseline,
                       "note", "start")
          end
        end

        # A dashed line from each note to the class it is attached to.
        def build_note_links(notes, boxes)
          by_name = boxes.to_h { |box| [box.id, box] }
          notes.each_with_index.map do |note, index|
            ends = [by_name.fetch("note-#{index}"), by_name.fetch(note.target)]
            edge = relation_endpoints(*ends)
            Scene::Relation.new(id: "note-link-#{index}", dashed: true,
                                path: relation_path(edge),
                                texts: [], markers: [])
          end
        end

        def box_contents(item, horizontal, vertical, width)
          return [note_texts(item, horizontal, vertical), []] if item[:note]

          texts, cursor = title_texts(item, horizontal, vertical, width)
          members, separators = member_contents(
            item, horizontal, cursor, width
          )
          [texts + members, separators]
        end

        def title_texts(item, horizontal, vertical, width)
          cursor = vertical + BOX_PADDING + font_size
          texts, cursor = title_text_rows(item, horizontal, width, cursor)
          texts << floating_generic_text(item, horizontal, vertical, width)
          [texts.compact, cursor]
        end

        def title_text_rows(item, horizontal, width, cursor)
          texts = item[:title_rows].each_with_index.map do |content, index|
            text = scene_text(content, horizontal + (width / 2), cursor,
                              title_role(item, index), "middle")
            cursor += ROW_HEIGHT
            text
          end
          [texts, cursor]
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

          separator = member_separator(horizontal, cursor, width)
          [member_texts(item, horizontal, cursor),
           [separator, *underlines(item, horizontal, cursor)]]
        end

        def member_separator(horizontal, cursor, width)
          vertical = cursor - (ROW_HEIGHT / 2)
          segment(horizontal, vertical, horizontal + width, vertical)
        end

        def member_texts(item, horizontal, cursor)
          item[:member_rows].each_with_index.map do |content, index|
            role = item[:member_modifiers][index].include?(:abstract)
            vertical = cursor + 6.0 + (index * ROW_HEIGHT)
            scene_text(content, horizontal + BOX_PADDING, vertical,
                       role ? "member_abstract" : "member", "start")
          end
        end

        # A static member is underlined, as PlantUML draws it.
        def underlines(item, horizontal, cursor)
          item[:member_rows].each_with_index.filter_map do |content, index|
            next unless item[:member_modifiers][index].include?(:static)

            vertical = cursor + 8.0 + (index * ROW_HEIGHT)
            left = horizontal + BOX_PADDING
            segment(left, vertical, left + measured_width(content), vertical)
          end
        end

        def build_relations(diagram, boxes, nodes)
          by_name = boxes.to_h { |box| [box.id.delete_prefix("package-"), box] }
          owners = junction_owners(diagram)
          engine = RankChain.engine(diagram)
          context = { by_name: by_name, owners: owners, nodes: nodes,
                      engine: engine }
          diagram.relations.each_with_index.flat_map do |relation, index|
            next [] if relation.layout_only?

            relation_scenes(relation, index, context)
          end
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
          junction = junction_box(context.fetch(:nodes)[index], ends)
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
        def junction_box(node, ends)
          node ||= [*midpoint(*relation_endpoints(*ends).values_at(:left,
                                                                   :right)),
                    0.0, 0.0]
          x, y, width, height = node
          Scene::Box.new(id: "junction", x: x, y: y, width: width,
                         height: height, texts: [], separators: [],
                         kind: "junction")
        end

        def relation_scene(relation, id, endpoints, end_texts, style = {})
          sides = style.fetch(:sides, %i[left right])
          markers = style.fetch(:markers, relation.markers)
          texts = relation_texts(relation, endpoints, end_texts, sides)
          drawn_markers = relation_markers(relation, markers, sides, endpoints)
          Scene::Relation.new(id: id, dashed: relation.dashed?, texts: texts,
                              path: relation_path_for(relation, endpoints),
                              markers: drawn_markers)
        end

        def relation_markers(relation, markers, sides, endpoints)
          half_width = qualified_marker_half_width(relation, endpoints)
          drawn_markers = marker_scenes(markers.slice(*sides), endpoints,
                                        half_width: half_width)
          drawn_markers << label_arrow_scene(relation, endpoints)
          drawn_markers.compact
        end

        def relation_path_for(relation, endpoints)
          ordered = if reversed_qualified?(relation)
                      endpoints.merge(left: endpoints[:right],
                                      right: endpoints[:left])
                    else
                      endpoints
                    end
          control = qualified_label_control(relation, ordered)
          return relation_path(ordered) unless control

          "M #{point(ordered[:left])} Q #{point(control)} " \
            "#{point(ordered[:right])}"
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
          return unless qualifiers.all? { |text| text&.start_with?("[") }

          left, right = endpoints.values_at(:left, :right)
          9.0 unless steep?(left, right)
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
          centre = shift(centre, 1.0, 0.0, 25.0) if steep?(left, right)
          [centre, direction]
        end

        # PlantUML turns a relation carrying an association class into two
        # legs meeting at a junction node, each keeping its own end's text,
        # plus a dashed link from that node to each association class. An
        # `up` or `left` word moves each end's marker to the other leg, as
        # the pinned references draw it.
        def junction_scenes(relation, index, boxes, owners)
          (from, to), junction, end_texts = boxes
          swap = %i[up left].include?(relation.direction)
          markers = relation.markers
          [relation_scene(
            relation, "relation-#{index}-from",
            relation_endpoints(from, junction), end_texts,
            sides: %i[left], markers: junction_markers(markers, swap, :left)
          ),
           relation_scene(
             relation, "relation-#{index}-to",
             relation_endpoints(junction, to), end_texts,
             sides: %i[right], markers: junction_markers(markers, swap, :right)
           ),
           *owners.map { |entry| owner_link(junction, *entry) }]
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

          {
            left: boundary_point(left_box, right_box),
            right: boundary_point(right_box, left_box),
          }
        end

        def self_relation_endpoints(box)
          endpoints = { left: right_edge_point(box, 0.35) }
          endpoints[:right] = right_edge_point(box, 0.7)
          endpoints[:control] = right_edge_point(box, 0.5, offset: 54.0)
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
            other = endpoints.fetch(side == :left ? :right : :left)
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
          length = Math.hypot(delta_horizontal, delta_vertical)
          return [1.0, 0.0] if length.zero?

          [delta_horizontal / length, delta_vertical / length]
        end

        def shift(origin, direction_horizontal, direction_vertical, distance)
          [origin[0] + (direction_horizontal * distance),
           origin[1] + (direction_vertical * distance)]
        end

        # The label rides with the left end, so a relation split into legs
        # still shows it once.
        def relation_texts(relation, endpoints, end_texts, sides)
          first, second = end_texts.sides
          direction = unit_vector(*endpoints.values_at(first, second))
          label = relation_text_label(relation, endpoints, sides)
          texts = positioned_end_texts(end_texts.entries, endpoints,
                                       direction, first, sides)
          [label, *texts].compact
        end

        def relation_text_label(relation, endpoints, sides)
          return unless sides.include?(:left)

          relation_label(visible_relation_label(relation.label),
                         *endpoints.values_at(:left, :right))
        end

        def visible_relation_label(label)
          label&.sub(/[ \t]+[<>]\z/, "")
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
        def relation_label(content, left, right)
          return unless content

          horizontal, middle = midpoint(left, right)
          if steep?(left, right)
            return steep_relation_label(content, horizontal, middle)
          end

          scene_text(content, horizontal, middle - LABEL_OFFSET,
                     "relation_label", "middle")
        end

        def steep?(left, right)
          horizontal, vertical = vector_between(left, right)
          vertical.abs > horizontal.abs
        end

        def steep_relation_label(content, horizontal, middle)
          size = font_size * SMALL_TEXT_SCALE
          baseline = middle + (size * (1 - TEXT_DESCENT) / 2)
          scene_text(content, horizontal + LABEL_GAP, baseline,
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
