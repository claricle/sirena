# frozen_string_literal: true

require_relative "../../layout/base"
require_relative "caption_layout"
require_relative "class_name"
require_relative "ir_reader"
require_relative "package_frames"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      # Positions PlantUML class boxes and relations in final canvas space,
      # from the IR::Graph {IRAdapter} emits.
      class Layout < Sirena::Layout::Base
        MARGIN = 36.0
        COLUMN_GAP = 90.0
        ROW_GAP = 90.0
        MIN_BOX_WIDTH = 160.0
        BOX_PADDING = 12.0
        ROW_HEIGHT = 22.0
        MARKER_LENGTH = 12.0
        MARKER_HALF_WIDTH = 7.0
        LABEL_OFFSET = 10.0
        NESTING_RADIUS = 8.0
        MEMBER_NOTE_TEXT_SCALE = 1.15
        MEMBER_NOTE_ROW_HEIGHT = 16.48828125
        MEMBER_NOTE_LINE_HEIGHT = 15.310546875
        MEMBER_NOTE_STACK_GAP = 10.0
        MEMBER_NOTE_BODY_GAP = 35.0
        MEMBER_NOTE_CLASS_HEIGHT = 48.0
        MEMBER_NOTE_SIDE_PADDING = 6.0
        FILLED_MARKERS = %i[association dependency composition].freeze
        private_constant :MARGIN, :COLUMN_GAP, :ROW_GAP, :MIN_BOX_WIDTH,
                         :BOX_PADDING, :ROW_HEIGHT, :MARKER_LENGTH,
                         :MARKER_HALF_WIDTH, :LABEL_OFFSET, :FILLED_MARKERS,
                         :NESTING_RADIUS, :MEMBER_NOTE_TEXT_SCALE,
                         :MEMBER_NOTE_ROW_HEIGHT, :MEMBER_NOTE_LINE_HEIGHT,
                         :MEMBER_NOTE_STACK_GAP, :MEMBER_NOTE_BODY_GAP,
                         :MEMBER_NOTE_CLASS_HEIGHT,
                         :MEMBER_NOTE_SIDE_PADDING

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
          specifications = diagram.classes.map do |klass|
            box_specification(klass, diagram)
          end
          specifications += note_specifications(diagram.notes)
          box_width = widest_box(specifications)
          boxes = position_boxes(rows_by_package(specifications, diagram),
                                 box_width)

          build_scene(diagram, boxes, box_width)
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

        def scene_relations(diagram, boxes)
          build_relations(diagram.relations, boxes) +
            build_junctions(diagram, boxes) +
            build_note_links(diagram.notes, boxes)
        end

        def box_specification(klass, diagram)
          member_rows = klass.body.map { |member| member_text(member) }
          names = name_rows(klass)
          box_record(klass.name, header_rows(klass) + names, member_rows)
            .merge(name_rows: names.size, **box_context(klass, diagram))
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
          [MIN_BOX_WIDTH, measured.max.to_f + (BOX_PADDING * 2)].max
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

        def name_rows(klass)
          *first, last = ClassName.lines(klass.name)
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

        def position_boxes(rows, box_width)
          tops = row_tops(rows)
          left = left_margin(rows)
          rows.each_with_index.flat_map do |row, row_index|
            row.each_with_index.filter_map do |item, column|
              x = left + (column * (box_width + COLUMN_GAP))
              build_box(item, x, tops[row_index], box_width) if item
            end
          end
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
          texts = item[:title_rows].each_with_index.map do |content, index|
            role = title_role(item, index)
            text = scene_text(
              content, horizontal + (width / 2), cursor, role, "middle"
            )
            cursor += ROW_HEIGHT
            text
          end
          [texts, cursor]
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

        def build_relations(relations, boxes)
          by_name = boxes.to_h { |box| [box.id.delete_prefix("package-"), box] }
          relations.each_with_index.map do |relation, index|
            build_relation(relation, index, by_name)
          end
        end

        def build_relation(relation, index, by_name)
          left_box = by_name.fetch(relation.left)
          right_box = by_name.fetch(relation.right)
          endpoints = relation_endpoints(left_box, right_box)

          relation_scene(relation, index, endpoints)
        end

        def relation_scene(relation, index, endpoints)
          texts = relation_texts(relation, endpoints)
          Scene::Relation.new(id: "relation-#{index}", dashed: relation.dashed?,
                              path: relation_path(endpoints), texts: texts,
                              markers: marker_scenes(relation, endpoints))
        end

        # A dashed line from the association class to the middle of the
        # relation it hangs on.
        def build_junctions(diagram, boxes)
          by_name = boxes.to_h { |box| [box.id, box] }
          diagram.junctions.each_with_index.map do |junction, index|
            junction_scene(junction, index, by_name)
          end
        end

        def junction_scene(junction, index, by_name)
          ends = [junction.from, junction.to].map { |n| by_name.fetch(n) }
          middle = midpoint(*relation_endpoints(*ends).values_at(:left, :right))
          owner = by_name.fetch(junction.owner)
          edge = boundary_toward(owner, middle)
          Scene::Relation.new(id: "junction-#{index}", dashed: true,
                              path: "M #{point(edge)} L #{point(middle)}",
                              texts: [], markers: [])
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

        def marker_scenes(relation, endpoints)
          relation.markers.map do |side, kind|
            tip = endpoints.fetch(side)
            other = endpoints.fetch(side == :left ? :right : :left)
            marker_scene(kind, tip, other)
          end
        end

        def marker_scene(kind, tip, other)
          return nesting_scene(tip, other) if kind == :nesting

          Scene::Marker.new(
            shape: "polygon", filled: FILLED_MARKERS.include?(kind),
            points: marker_points(tip, other, marker_shape(kind))
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

          :triangle
        end

        def marker_points(tip, other, shape)
          direction = unit_vector(other, tip)
          base = shift(tip, *direction, -MARKER_LENGTH)
          left = marker_side(base, direction, MARKER_HALF_WIDTH)
          right = marker_side(base, direction, -MARKER_HALF_WIDTH)
          points = [tip, left]
          points << diamond_back(tip, direction) if shape == :diamond
          points << right
          formatted_points(points)
        end

        def marker_side(base, direction, distance)
          shift(base, -direction[1], direction[0], distance)
        end

        def diamond_back(tip, direction)
          shift(tip, *direction, -(MARKER_LENGTH * 2))
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

        def relation_texts(relation, endpoints)
          left = endpoints.fetch(:left)
          right = endpoints.fetch(:right)
          direction = unit_vector(left, right)

          [relation_label(relation.label, left, right),
           multiplicity(end_text(relation, :left), left, direction, 1),
           multiplicity(end_text(relation, :right), right, direction, -1)]
            .compact
        end

        def end_text(relation, side)
          parts = [relation.public_send(:"#{side}_multiplicity"),
                   relation.public_send(:"#{side}_role")].compact
          parts.join(" ") unless parts.empty?
        end

        def relation_label(content, left, right)
          return unless content

          horizontal = (left[0] + right[0]) / 2
          vertical = ((left[1] + right[1]) / 2) - LABEL_OFFSET
          scene_text(
            content, horizontal, vertical, "relation_label", "middle"
          )
        end

        def multiplicity(content, endpoint, vector, direction)
          return unless content

          along = shift(endpoint, *vector, 18.0 * direction)
          offset = shift(along, -vector[1], vector[0], -LABEL_OFFSET)
          scene_text(content, offset[0], offset[1], "multiplicity", "middle")
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

        def canvas_width(boxes, box_width)
          (boxes.map(&:x).min * 2) + (column_count(boxes) * box_width) +
            ((column_count(boxes) - 1) * COLUMN_GAP)
        end

        def widest_box(specifications)
          widths = specifications.map { |item| item[:width] }
          [MIN_BOX_WIDTH, *widths].max
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
