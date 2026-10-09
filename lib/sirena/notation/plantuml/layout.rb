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
          specifications = diagram.classes.map { |klass| box_specification(klass) }
          box_width = [MIN_BOX_WIDTH, *specifications.map { |item| item[:width] }].max
          boxes = position_boxes(specifications, box_width)
          rows = boxes.each_slice(column_count(boxes)).to_a

          Scene.new(
            width: canvas_width(boxes, box_width),
            height: canvas_height(rows),
            boxes: boxes,
            relations: build_relations(diagram.relations, boxes),
          )
        end

        private

        def box_specification(klass)
          member_rows = klass.body.map { |member| member_text(member) }
          title_rows = title_rows(klass)
          rows = title_rows + member_rows
          measured = rows.map { |text| measured_width(text) }
          height = (BOX_PADDING * 2) + (rows.size * ROW_HEIGHT)
          height += 6.0 unless member_rows.empty?

          {
            id: klass.name,
            width: [MIN_BOX_WIDTH, measured.max.to_f + (BOX_PADDING * 2)].max,
            height: height,
            title_rows: title_rows,
            member_rows: member_rows,
          }
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
          row_heights = specifications.each_slice(columns).map do |row|
            row.map { |item| item[:height] }.max
          end
          row_tops = row_heights.each_with_object([MARGIN]) do |height, tops|
            tops << tops.last + height + ROW_GAP
          end

          specifications.each_with_index.map do |item, index|
            build_box(item, index, columns, row_tops, box_width)
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

        def box_contents(item, x, y, width)
          cursor = y + BOX_PADDING + font_size
          texts = item[:title_rows].each_with_index.map do |content, index|
            role = index == item[:title_rows].size - 1 ? "class_name" : "kind"
            text = scene_text(content, x + (width / 2), cursor, role, "middle")
            cursor += ROW_HEIGHT
            text
          end

          separators = []
          unless item[:member_rows].empty?
            separator_y = cursor - (ROW_HEIGHT / 2)
            separators << segment(x, separator_y, x + width, separator_y)
            cursor += 6.0
            texts.concat(item[:member_rows].map do |content|
              text = scene_text(content, x + BOX_PADDING, cursor, "member", "start")
              cursor += ROW_HEIGHT
              text
            end)
          end
          [texts, separators]
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
          marker = marker_geometry(relation, endpoints)

          Scene::Relation.new(
            id: "relation-#{index}",
            path: relation_path(endpoints),
            dashed: relation.kind == :implementation,
            marker_points: marker[:points],
            marker_filled: marker[:filled],
            texts: relation_texts(relation, endpoints),
          )
        end

        def relation_endpoints(left_box, right_box)
          return self_relation_endpoints(left_box) if left_box.equal?(right_box)

          {
            left: boundary_point(left_box, right_box),
            right: boundary_point(right_box, left_box),
          }
        end

        def self_relation_endpoints(box)
          {
            left: [box.x + box.width, box.y + (box.height * 0.35)],
            right: [box.x + box.width, box.y + (box.height * 0.7)],
            control: [box.x + box.width + 54.0, box.y + (box.height / 2)],
          }
        end

        def boundary_point(box, target)
          centre = box_centre(box)
          other = box_centre(target)
          dx = other[0] - centre[0]
          dy = other[1] - centre[1]
          scale_x = (box.width / 2) / dx.abs unless dx.zero?
          scale_y = (box.height / 2) / dy.abs unless dy.zero?
          scale = [scale_x, scale_y].compact.min
          [centre[0] + (dx * scale), centre[1] + (dy * scale)]
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
          shape = %i[aggregation composition].include?(relation.kind) ? :diamond : :triangle
          points = marker_points(tip, other, shape)
          filled = %i[association composition].include?(relation.kind)
          { points: points, filled: filled }
        end

        def marker_points(tip, other, shape)
          ux, uy = unit_vector(other, tip)
          perpendicular = [-uy, ux]
          base = shift(tip, ux, uy, -MARKER_LENGTH)
          left = shift(base, *perpendicular, MARKER_HALF_WIDTH)
          right = shift(base, *perpendicular, -MARKER_HALF_WIDTH)
          points = [tip, left]
          points << shift(tip, ux, uy, -(MARKER_LENGTH * 2)) if shape == :diamond
          points << right
          points.map { |coordinate| point(coordinate, separator: ",") }.join(" ")
        end

        def unit_vector(from, to)
          dx = to[0] - from[0]
          dy = to[1] - from[1]
          length = Math.hypot(dx, dy)
          return [1.0, 0.0] if length.zero?

          [dx / length, dy / length]
        end

        def shift(origin, ux, uy, distance)
          [origin[0] + (ux * distance), origin[1] + (uy * distance)]
        end

        def relation_texts(relation, endpoints)
          left = endpoints.fetch(:left)
          right = endpoints.fetch(:right)
          ux, uy = unit_vector(left, right)
          texts = []
          texts << relation_label(relation.label, left, right) if relation.label
          if relation.left_multiplicity
            texts << multiplicity(relation.left_multiplicity, left, ux, uy, 1)
          end
          if relation.right_multiplicity
            texts << multiplicity(relation.right_multiplicity, right, ux, uy, -1)
          end
          texts
        end

        def relation_label(content, left, right)
          x = (left[0] + right[0]) / 2
          y = ((left[1] + right[1]) / 2) - LABEL_OFFSET
          scene_text(content, x, y, "relation_label", "middle")
        end

        def multiplicity(content, endpoint, ux, uy, direction)
          along = shift(endpoint, ux, uy, 18.0 * direction)
          offset = shift(along, -uy, ux, -LABEL_OFFSET)
          scene_text(content, offset[0], offset[1], "multiplicity", "middle")
        end

        def scene_text(content, x, y, role, anchor)
          Scene::Text.new(content: content, x: x, y: y, role: role,
                          anchor: anchor)
        end

        def segment(x1, y1, x2, y2)
          Scene::Segment.new(x1: x1, y1: y1, x2: x2, y2: y2)
        end

        def point(coordinates, separator: " ")
          coordinates.map { |number| number.round(3) }.join(separator)
        end

        def canvas_width(boxes, box_width)
          (MARGIN * 2) + (column_count(boxes) * box_width) +
            ((column_count(boxes) - 1) * COLUMN_GAP)
        end

        def canvas_height(rows)
          rows.sum { |row| row.map(&:height).max } +
            ((rows.size - 1) * ROW_GAP) + (MARGIN * 2)
        end
      end
    end
  end
end
