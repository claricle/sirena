# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Places the small graph family whose bracketed relation qualifiers
      # make PlantUML honour written direction words and one-dash same-rank
      # links. Ordinary two-dash links advance down a rank; each extra dash
      # advances one more rank.
      class QualifiedAssociationLayout
        RADIAL_HORIZONTAL_GAP = 80.0
        FAN_HORIZONTAL_GAP = 35.0
        MIXED_HORIZONTAL_GAP = 70.0
        COMPACT_HORIZONTAL_GAP = 130.0
        STANDARD_VERTICAL_GAP = 100.0
        MIXED_NEAR_VERTICAL_GAP = 60.0
        MIXED_LONG_VERTICAL_GAP = 80.0
        COMPACT_VERTICAL_GAP = 120.0
        COMPONENT_GAP = 25.0
        FAN_PARENT_ALLOWANCE = 35.0
        private_constant :RADIAL_HORIZONTAL_GAP, :FAN_HORIZONTAL_GAP,
                         :MIXED_HORIZONTAL_GAP, :COMPACT_HORIZONTAL_GAP,
                         :STANDARD_VERTICAL_GAP,
                         :MIXED_NEAR_VERTICAL_GAP,
                         :MIXED_LONG_VERTICAL_GAP,
                         :COMPACT_VERTICAL_GAP, :COMPONENT_GAP,
                         :FAN_PARENT_ALLOWANCE

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
          @classes = diagram.classes
          @relations = diagram.relations
          @directives = diagram.directives
        end

        # Fan-out parents span the compact row occupied by their targets.
        # This is the node constraint dot applies before it places ranks.
        def constrained_sizes(sizes)
          constrained = sizes.transform_values(&:dup)
          fan_relations.each do |parent, outgoing|
            children = outgoing.map(&:right)
            child_width = children.sum { |name| constrained.fetch(name).first }
            row_width = child_width +
              (FAN_HORIZONTAL_GAP * (children.size - 1))
            parent_size = constrained.fetch(parent)
            parent_size[0] = [parent_size.first,
                              row_width + FAN_PARENT_ALLOWANCE].max
          end
          constrained
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

        attr_reader :names, :classes, :relations, :directives

        def fan_relations
          relations.group_by(&:left).select do |_parent, outgoing|
            outgoing.size > 2 && outgoing.all? do |relation|
              relation.direction.nil? && relation.length > 1
            end
          end
        end

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
                                axis: 0,
                                origin: origin.first)
          rows = axis_layout(component, logical, sizes,
                             axis: 1,
                             origin: origin.last)
          corners = component.to_h do |name|
            [name, [centred(name, logical, sizes, columns, 0),
                    centred(name, logical, sizes, rows, 1)]]
          end
          width = axis_extent(columns, origin.first)
          corners, width = span_fan_parent(component, corners, width)
          [corners, width]
        end

        def span_fan_parent(component, corners, width)
          return [corners, width] unless fan_component?(component)

          inset = FAN_PARENT_ALLOWANCE / 2
          shifted = corners.transform_values { |left, top| [left + inset, top] }
          [shifted, width + FAN_PARENT_ALLOWANCE]
        end

        def axis_layout(component, logical, sizes, options)
          axis = options.fetch(:axis)
          data = { component: component, logical: logical, sizes: sizes }
          layout = { cursor: options.fetch(:origin) }
          coordinates = axis_coordinates(data, axis)
          coordinates.each do |coordinate|
            gap = axis_gap(component, axis, coordinate, coordinates, logical)
            place_axis(layout, data, coordinate, axis, gap)
          end
          layout
        end

        def axis_coordinates(data, axis)
          data.fetch(:component).map do |name|
            data.fetch(:logical).fetch(name)[axis]
          end.uniq.sort
        end

        def place_axis(layout, data, coordinate, axis, gap)
          span = axis_span(data.fetch(:component), data.fetch(:logical),
                           data.fetch(:sizes), axis, coordinate)
          layout[coordinate] = [layout.fetch(:cursor), span]
          layout[:cursor] += span + gap
        end

        def axis_gap(component, axis, coordinate, coordinates, logical)
          return 0.0 if coordinate == coordinates.last
          return horizontal_gap(component) if axis.zero?

          vertical_gap(component, coordinate, coordinates, logical)
        end

        def horizontal_gap(component)
          return COMPACT_HORIZONTAL_GAP if compact?
          return MIXED_HORIZONTAL_GAP if mixed_kind?
          return FAN_HORIZONTAL_GAP if fan_component?(component)

          RADIAL_HORIZONTAL_GAP
        end

        def vertical_gap(component, coordinate, coordinates, logical)
          return COMPACT_VERTICAL_GAP if compact?
          return STANDARD_VERTICAL_GAP unless mixed_kind?

          first = coordinates.first
          return MIXED_LONG_VERTICAL_GAP if coordinate == first &&
            long_qualified_source?(component, logical)

          MIXED_NEAR_VERTICAL_GAP
        end

        def fan_component?(component)
          fan_relations.keys.any? { |parent| component.include?(parent) }
        end

        def compact?
          directives.include?("hide empty members")
        end

        def mixed_kind?
          classes.any? { |klass| klass.kind != :class }
        end

        def long_qualified_source?(component, logical)
          top = component.min_by { |name| logical.fetch(name).last }
          relations.any? do |relation|
            relation.left == top && relation.length > 2 &&
              self.class.send(:qualifier?, relation)
          end
        end

        def axis_span(component, logical, sizes, axis, coordinate)
          names = component.select do |name|
            logical.fetch(name)[axis] == coordinate
          end
          names.delete(fan_parent(component)) if fan_parent_in_column?(
            component, names, axis
          )
          names.filter_map do |name|
            sizes.fetch(name)[axis] if logical.fetch(name)[axis] == coordinate
          end.max
        end

        def fan_parent_in_column?(component, names, axis)
          axis.zero? && names.size > 1 && fan_parent(component)
        end

        def fan_parent(component)
          fan_relations.keys.find { |name| component.include?(name) }
        end

        def centred(name, logical, sizes, layout, axis)
          left, span = layout.fetch(logical.fetch(name)[axis])
          left + ((span - sizes.fetch(name)[axis]) / 2)
        end

        def axis_extent(layout, origin)
          layout.fetch(:cursor) - origin
        end
      end
    end
  end
end
