# frozen_string_literal: true

require_relative "../../layout/base"
require_relative "package_frames"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      # Positions PlantUML class boxes and relations in final canvas space.
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
        FILLED_MARKERS = %i[association dependency composition].freeze
        private_constant :MARGIN, :COLUMN_GAP, :ROW_GAP, :MIN_BOX_WIDTH,
                         :BOX_PADDING, :ROW_HEIGHT, :MARKER_LENGTH,
                         :MARKER_HALF_WIDTH, :LABEL_OFFSET, :FILLED_MARKERS

        def scene(diagram)
          specifications = diagram.classes.map do |klass|
            box_specification(klass)
          end
          specifications += note_specifications(diagram.notes)
          box_width = widest_box(specifications)
          boxes = position_boxes(rows_by_package(specifications), box_width)

          build_scene(diagram, boxes, box_width)
        end

        private

        def build_scene(diagram, boxes, box_width)
          Scene.new(width: canvas_width(boxes, box_width),
                    height: scene_height(diagram, boxes), boxes: boxes,
                    relations: scene_relations(diagram, boxes),
                    frames: scene_frames(diagram, boxes))
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

        def box_specification(klass)
          member_rows = klass.body.map { |member| member_text(member) }
          title_rows = title_rows(klass)
          box_record(klass.name, title_rows, member_rows)
            .merge(member_modifiers: klass.body.map(&:modifiers),
                   package: klass.package)
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

        def title_rows(klass)
          kind = ["<<#{klass.kind}>>"] unless klass.kind == :class
          tags = klass.stereotypes.map { |tag| "<<#{tag}>>" }
          [*kind, *(tags.join(" ") unless tags.empty?), klass_title(klass)]
        end

        def klass_title(klass)
          klass.generics ? "#{klass.name}<#{klass.generics}>" : klass.name
        end

        def measured_width(text)
          measure_text(text, font_size: font_size, monospace: true)[:width]
        end

        def font_size
          theme.typography.font_size_normal.to_f
        end

        def member_text(member)
          text = "#{visibility_mark(member.visibility)}#{member.name}"
          text += "(#{member.parameters})" if member.parameters
          text += " : #{member.type}" if member.type
          text
        end

        def visibility_mark(visibility)
          { public: "+", private: "-", protected: "#", package: "~" }
            .fetch(visibility, "")
        end

        # Classes outside any package first, then each package's classes,
        # every group padded to whole rows so a row holds one group only.
        def rows_by_package(specifications)
          columns = column_count(specifications)
          package_groups(specifications).flat_map do |group|
            group.each_slice(columns).map { |row| pad(row, columns) }
          end
        end

        def package_groups(specifications)
          loose, packaged = specifications.partition { |i| !i[:package] }
          [loose, *packaged.group_by { |i| i[:package] }.values]
            .reject(&:empty?)
        end

        def pad(row, columns)
          row + Array.new(columns - row.size)
        end

        def position_boxes(rows, box_width)
          tops = row_tops(rows)
          rows.each_with_index.flat_map do |row, row_index|
            row.each_with_index.filter_map do |item, column|
              build_box(item, column, tops[row_index], box_width) if item
            end
          end
        end

        def row_tops(rows)
          packages = rows.map { |row| row.compact.first[:package] }
          first = [MARGIN + frame_space(nil, packages.first)]
          row_steps(rows, packages).each_with_object(first) do |step, tops|
            tops << (tops.last + step)
          end
        end

        def row_steps(rows, packages)
          row_heights(rows).each_with_index.map do |height, index|
            space = frame_space(packages[index], packages[index + 1])
            height + ROW_GAP + space
          end
        end

        def row_heights(rows)
          rows.map { |row| row.compact.map { |item| item[:height] }.max }
        end

        def frame_space(above, below)
          return 0.0 if above == below

          (above ? PackageFrames::CLOSE : 0.0) +
            (below ? PackageFrames::OPEN : 0.0)
        end

        def column_count(items)
          items.compact.size > 1 ? 2 : 1
        end

        def build_box(item, column, top, box_width)
          x = MARGIN + (column * (box_width + COLUMN_GAP))
          texts, separators = box_contents(item, x, top, box_width)

          Scene::Box.new(
            id: item[:id], x: x, y: top, width: box_width,
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
                                marker_filled: false, texts: [])
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
            role = index == item[:title_rows].size - 1 ? "class_name" : "kind"
            text = scene_text(
              content, horizontal + (width / 2), cursor, role, "middle"
            )
            cursor += ROW_HEIGHT
            text
          end
          [texts, cursor]
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
          by_name = boxes.to_h { |box| [box.id, box] }
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
          marker = marker_geometry(relation, endpoints)
          path = relation_path(endpoints)
          dashed = %i[implementation dependency].include?(relation.kind)
          texts = relation_texts(relation, endpoints)
          Scene::Relation.new(id: "relation-#{index}", path: path,
                              dashed: dashed, marker_points: marker[:points],
                              marker_filled: marker[:filled], texts: texts)
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
                              marker_filled: false, texts: [])
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

        def marker_geometry(relation, endpoints)
          side = relation.head
          return { points: nil, filled: false } unless side

          tip = endpoints.fetch(side)
          other = endpoints.fetch(side == :left ? :right : :left)
          shape = marker_shape(relation.kind)
          points = marker_points(tip, other, shape)
          filled = FILLED_MARKERS.include?(relation.kind)
          { points: points, filled: filled }
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
          (MARGIN * 2) + (column_count(boxes) * box_width) +
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
