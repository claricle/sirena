# frozen_string_literal: true

require_relative "../../layout/base"
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
        private_constant :MARGIN, :COLUMN_GAP, :ROW_GAP, :MIN_BOX_WIDTH,
                         :BOX_PADDING, :ROW_HEIGHT, :MARKER_LENGTH,
                         :MARKER_HALF_WIDTH, :LABEL_OFFSET

        def scene(diagram)
          specifications = diagram.classes.map do |klass|
            box_specification(klass)
          end
          box_width = widest_box(specifications)
          boxes = position_boxes(specifications, box_width)

          build_scene(diagram, boxes, box_width)
        end

        private

        def build_scene(diagram, boxes, box_width)
          width = canvas_width(boxes, box_width)
          height = canvas_height(box_rows(boxes))
          relations = build_relations(diagram.relations, boxes)
          Scene.new(width: width, height: height, boxes: boxes,
                    relations: relations)
        end

        def box_specification(klass)
          member_rows = klass.body.map { |member| member_text(member) }
          title_rows = title_rows(klass)
          box_record(klass.name, title_rows, member_rows)
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
          return [klass.name] if klass.kind == :class

          ["<<#{klass.kind}>>", klass.name]
        end

        def measured_width(text)
          measure_text(text, font_size: font_size, monospace: true)[:width]
        end

        def font_size
          theme.typography.font_size_normal.to_f
        end

        def member_text(member)
          text = "#{visibility_mark(member.visibility)}#{member.name}"
          text += "(#{member.parameters})" if member.kind == :method
          text += " : #{member.type}" if member.type
          text
        end

        def visibility_mark(visibility)
          { public: "+", private: "-", protected: "#", package: "~" }
            .fetch(visibility, "")
        end

        def position_boxes(specifications, box_width)
          columns = column_count(specifications)
          row_tops = row_tops(specifications, columns)

          specifications.each_with_index.map do |item, index|
            build_box(item, index, columns, row_tops, box_width)
          end
        end

        def row_tops(specifications, columns)
          heights = specifications.each_slice(columns).map do |row|
            row.map { |item| item[:height] }.max
          end
          heights.each_with_object([MARGIN]) do |height, tops|
            tops << (tops.last + height + ROW_GAP)
          end
        end

        def column_count(items)
          items.size > 1 ? 2 : 1
        end

        def build_box(item, index, columns, row_tops, box_width)
          x = MARGIN + ((index % columns) * (box_width + COLUMN_GAP))
          y = row_tops[index / columns]
          texts, separators = box_contents(item, x, y, box_width)

          Scene::Box.new(
            id: item[:id], x: x, y: y, width: box_width,
            height: item[:height], texts: texts, separators: separators
          )
        end

        def box_contents(item, horizontal, vertical, width)
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
          [member_texts(item, horizontal, cursor), [separator]]
        end

        def member_separator(horizontal, cursor, width)
          vertical = cursor - (ROW_HEIGHT / 2)
          segment(horizontal, vertical, horizontal + width, vertical)
        end

        def member_texts(item, horizontal, cursor)
          item[:member_rows].each_with_index.map do |content, index|
            vertical = cursor + 6.0 + (index * ROW_HEIGHT)
            scene_text(content, horizontal + BOX_PADDING, vertical,
                       "member", "start")
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
          dashed = relation.kind == :implementation
          texts = relation_texts(relation, endpoints)
          Scene::Relation.new(id: "relation-#{index}", path: path,
                              dashed: dashed, marker_points: marker[:points],
                              marker_filled: marker[:filled], texts: texts)
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
          centre = box_centre(box)
          delta = vector_between(centre, box_centre(target))
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
          filled = %i[association composition].include?(relation.kind)
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
           multiplicity(relation.left_multiplicity, left, direction, 1),
           multiplicity(relation.right_multiplicity, right, direction, -1)]
            .compact
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
          boxes.each_slice(column_count(boxes)).to_a
        end

        def canvas_height(rows)
          rows.sum { |row| row.map(&:height).max } +
            ((rows.size - 1) * ROW_GAP) + (MARGIN * 2)
        end
      end
    end
  end
end
