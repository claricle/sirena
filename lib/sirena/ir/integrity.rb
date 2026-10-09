# frozen_string_literal: true

module Sirena
  module IR
    module Integrity
      ENDPOINT_FIELDS = %i[source_id target_id].freeze

      module_function

      def unique_id_errors(items)
        duplicates = items.group_by(&:id).select do |_id, members|
          members.length > 1
        end.keys
        duplicates.map { |id| ArgumentError.new("duplicate id: #{id}") }
      end

      def parent_errors(items, parents: items)
        parent_ids = parents.map(&:id).to_h { |id| [id, true] }
        errors = items.filter_map do |item|
          next if item.parent_id.nil? || parent_ids.key?(item.parent_id)

          message = "unresolved parent_id for #{item.id}: #{item.parent_id}"
          ArgumentError.new(message)
        end
        errors + cycle_errors(items)
      end

      def endpoint_errors(edges, endpoints:)
        endpoint_ids = endpoints.map(&:id).to_h { |id| [id, true] }
        edges.flat_map do |edge|
          ENDPOINT_FIELDS.filter_map do |name|
            endpoint = edge.public_send(name)
            next if endpoint_ids.key?(endpoint)

            ArgumentError.new("unresolved #{name} for #{edge.id}: #{endpoint}")
          end
        end
      end

      def reference_errors(values, dimensions:, series:)
        dimensions_by_id = dimensions.map(&:id).to_h { |id| [id, true] }
        series_by_id = series.map(&:id).to_h { |id| [id, true] }
        values.flat_map do |value|
          reference_error(value, :dimension_id, dimensions_by_id) +
            reference_error(value, :series_id, series_by_id)
        end
      end

      def cycle_errors(items)
        parents = items.to_h { |item| [item.id, item.parent_id] }
        items.filter_map do |item|
          next unless parent_cycle?(item.id, parents)

          ArgumentError.new("parent cycle includes #{item.id}")
        end
      end

      def parent_cycle?(start_id, parents)
        visited = {}
        current_id = start_id
        while current_id
          return true if visited[current_id]

          visited[current_id] = true
          current_id = parents[current_id]
        end
        false
      end

      def reference_error(value, name, known_ids)
        reference = value.public_send(name)
        return [] if reference.nil?
        return [] if known_ids.key?(reference)

        [ArgumentError.new("unresolved #{name} for #{value.id}: #{reference}")]
      end
      private_class_method :cycle_errors, :parent_cycle?, :reference_error
    end
  end
end
