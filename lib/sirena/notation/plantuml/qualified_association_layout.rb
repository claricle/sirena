# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Places the small graph family whose bracketed relation qualifiers
      # make PlantUML honour written direction words and one-dash same-rank
      # links. Ordinary two-dash links advance down a rank; each extra dash
      # advances one more rank.
      class QualifiedAssociationLayout
        HORIZONTAL_GAP = 100.0
        VERTICAL_GAP = 100.0
        COMPONENT_GAP = 60.0
        private_constant :HORIZONTAL_GAP, :VERTICAL_GAP, :COMPONENT_GAP

        def self.for(diagram)
          return unless isolated_class_graph?(diagram)
          return unless qualified_relations?(diagram.relations)

          new(diagram)
        end

        def self.isolated_class_graph?(diagram)
          diagram.packages.empty? && diagram.notes.empty? &&
            diagram.junctions.empty?
        end

        def self.qualified_relations?(relations)
          relations.any? { |relation| qualifier?(relation) } &&
            relations.none? do |relation|
              relation.left_role || relation.right_role
            end
        end

        def self.qualifier?(relation)
          [relation.left_multiplicity, relation.right_multiplicity]
            .compact.any? { |text| text.start_with?("[") }
        end
        private_class_method :isolated_class_graph?, :qualified_relations?,
                             :qualifier?

        def initialize(diagram)
          @names = diagram.classes.map(&:name)
          @relations = diagram.relations
        end

        # @param sizes [Hash{String => Array(Float, Float)}]
        # @param origin [Array(Float, Float)]
        # @return [Hash{String => Array(Float, Float)}] top-left corners
        def place(sizes, origin)
          edge = origin.first
          components.each_with_object({}) do |component, corners|
            logical = spread_collisions(logical_positions(component))
            placed, width = place_component(component, logical, sizes,
                                            [edge, origin.last])
            corners.merge!(placed)
            edge += width + COMPONENT_GAP
          end
        end

        private

        attr_reader :names, :relations

        def components
          unseen = names.dup
          unseen.each_with_object([]) do |name, found|
            next unless unseen.include?(name)

            component = reachable(name)
            found << component
            unseen -= component
          end
        end

        def reachable(root)
          seen = []
          queue = [root]
          until queue.empty?
            name = queue.shift
            next if seen.include?(name)

            seen << name
            queue.concat(neighbours(name))
          end
          seen
        end

        def neighbours(name)
          relations.filter_map do |relation|
            relation.right if relation.left == name
          end + relations.filter_map do |relation|
            relation.left if relation.right == name
          end
        end

        def logical_positions(component)
          positions = { component.first => [0.0, 0.0] }
          queue = [component.first]
          until queue.empty?
            name = queue.shift
            visit_connected(name, positions, queue)
          end
          positions
        end

        def visit_connected(name, positions, queue)
          connected(name).each do |other, delta|
            next if positions.key?(other)

            positions[other] = add(positions.fetch(name), delta)
            queue << other
          end
        end

        def connected(name)
          relations.filter_map do |relation|
            delta = relation_delta(relation)
            if relation.left == name
              [relation.right, delta]
            elsif relation.right == name
              [relation.left, delta.map(&:-@)]
            end
          end
        end

        def relation_delta(relation)
          case relation.direction
          when :up then [0.0, -1.0]
          when :down then [0.0, 1.0]
          when :left then [-1.0, 0.0]
          when :right then [1.0, 0.0]
          else default_delta(relation)
          end
        end

        def default_delta(relation)
          return [1.0, 0.0] if relation.length == 1

          [0.0, [relation.length - 1, 1].max.to_f]
        end

        def add(first, second)
          first.zip(second).map(&:sum)
        end

        def spread_collisions(positions)
          positions.group_by { |_name, point| point }.each_value do |entries|
            spread(entries, positions) if entries.size > 1
          end
          positions
        end

        def spread(entries, positions)
          middle = (entries.size - 1) / 2.0
          entries.each_with_index do |(name, point), index|
            positions[name] = [point.first + index - middle, point.last]
          end
        end

        def place_component(component, logical, sizes, origin)
          columns = axis_layout(component, logical, sizes,
                                axis: 0, gap: HORIZONTAL_GAP,
                                origin: origin.first)
          rows = axis_layout(component, logical, sizes,
                             axis: 1, gap: VERTICAL_GAP,
                             origin: origin.last)
          corners = component.to_h do |name|
            [name, [centred(name, logical, sizes, columns, 0),
                    centred(name, logical, sizes, rows, 1)]]
          end
          [corners, axis_extent(columns, origin.first)]
        end

        def axis_layout(component, logical, sizes, options)
          axis = options.fetch(:axis)
          data = { component: component, logical: logical, sizes: sizes }
          layout = { cursor: options.fetch(:origin) }
          axis_coordinates(data, axis).each do |coordinate|
            place_axis(layout, data, coordinate, options)
          end
          layout
        end

        def axis_coordinates(data, axis)
          data.fetch(:component).map do |name|
            data.fetch(:logical).fetch(name)[axis]
          end.uniq.sort
        end

        def place_axis(layout, data, coordinate, options)
          axis = options.fetch(:axis)
          span = axis_span(data.fetch(:component), data.fetch(:logical),
                           data.fetch(:sizes), axis, coordinate)
          layout[coordinate] = [layout.fetch(:cursor), span]
          layout[:cursor] += span + options.fetch(:gap)
        end

        def axis_span(component, logical, sizes, axis, coordinate)
          component.filter_map do |name|
            sizes.fetch(name)[axis] if logical.fetch(name)[axis] == coordinate
          end.max
        end

        def centred(name, logical, sizes, layout, axis)
          left, span = layout.fetch(logical.fetch(name)[axis])
          left + ((span - sizes.fetch(name)[axis]) / 2)
        end

        def axis_extent(layout, origin)
          layout.fetch(:cursor) - origin - HORIZONTAL_GAP
        end
      end
    end
  end
end
