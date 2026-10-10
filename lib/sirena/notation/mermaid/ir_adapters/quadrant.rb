# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module Mermaid
      module IRAdapters
        # Maps a Quadrant model to ordered coordinate constraints.
        module Quadrant
          AXES = {
            x_min: :x_axis_left,
            x_max: :x_axis_right,
            y_min: :y_axis_bottom,
            y_max: :y_axis_top,
          }.freeze

          module_function

          def call(diagram)
            occupied = [diagram.id || "quadrant"]
            frame = container("coordinate_frame", "frame", occupied)
            series = container("point_series", "series", occupied,
                               parent_id: frame.id)
            items = [frame, *axis_items(diagram, frame.id, occupied),
                     *region_items(diagram, frame.id, occupied), series]
            items.concat(point_items(diagram, series.id, occupied))
            IR::Prepositioned.new(
              id: occupied.first, label: diagram.title,
              role: "coordinate_plane", items: items
            )
          end

          def axis_items(diagram, parent_id, occupied)
            AXES.map.with_index do |(position, reader), index|
              IR::PrepositionedItem.new(
                id: reserve_id("axis_#{position}", occupied),
                label: diagram.public_send(reader), role: "axis_label",
                parent_id: parent_id,
                placements: [placement("axis_position", index, position)]
              )
            end
          end

          def region_items(diagram, parent_id, occupied)
            (1..4).map do |number|
              IR::PrepositionedItem.new(
                id: reserve_id("region_#{number}", occupied),
                label: diagram.public_send("quadrant_#{number}_label"),
                role: "region_label", parent_id: parent_id,
                placements: [placement("region", number - 1, number)]
              )
            end
          end

          def point_items(diagram, parent_id, occupied)
            diagram.points.map.with_index do |point, index|
              IR::PrepositionedItem.new(
                id: reserve_id("point_#{index}", occupied),
                label: point.label, role: "point", parent_id: parent_id,
                placements: point_placements(point, index)
              )
            end
          end

          def point_placements(point, index)
            values = {
              x_value: point.x, y_value: point.y,
              marker_size: point.radius || 6,
              stroke_width: point.stroke_width || 2,
              fill_color: point.color, stroke_color: point.stroke_color
            }
            values.filter_map do |dimension, value|
              placement(dimension.to_s, index, value) unless value.nil?
            end
          end

          def container(role, dimension, occupied, parent_id: nil)
            IR::PrepositionedItem.new(
              id: reserve_id(role, occupied), role: role,
              parent_id: parent_id,
              placements: [placement(dimension, 0, 0)]
            )
          end

          def placement(dimension, ordinal, value)
            IR::Placement.new(
              dimension: dimension.to_s, ordinal: ordinal,
              value: scalar(value)
            )
          end

          def scalar(value)
            return IR::Scalar.new(number: value) if value.is_a?(Numeric)

            IR::Scalar.new(text: value.to_s)
          end

          def reserve_id(preferred, occupied)
            candidate = preferred.to_s
            suffix = 2
            while occupied.include?(candidate)
              candidate = "#{preferred}_#{suffix}"
              suffix += 1
            end
            occupied << candidate
            candidate
          end
          private_class_method :axis_items, :region_items, :point_items,
                               :point_placements, :container, :placement,
                               :scalar, :reserve_id
        end
      end
    end
  end
end
