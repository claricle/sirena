# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Matches the elements of two figures by the identity contract in
    # TODO.foundation/14. Geometry is deliberately left to the comparator.
    class ElementMatcher
      def self.match(reference:, sirena:)
        new(reference, sirena).match
      end

      def initialize(reference, sirena)
        @reference = reference
        @sirena = sirena
      end

      def match
        pairs = []
        failures = []
        ambiguous_count = 0

        scopes.each do |scope|
          result = match_scope(scope)
          pairs.concat(result[:pairs])
          failures.concat(result[:failures])
          ambiguous_count += result[:ambiguous_count]
        end

        {
          pairs: order_pairs(pairs),
          ambiguous_count: ambiguous_count,
          failures: failures,
        }
      end

      private

      attr_reader :reference, :sirena

      def scopes
        elements = reference.elements + sirena.elements
        elements.map { |element| scope_of(element) }.uniq
      end

      def scope_of(element)
        [element.kind, element.parent]
      end

      def match_scope(scope)
        reference_elements = in_scope(reference, scope)
        sirena_elements = in_scope(sirena, scope)
        match_by = match_mode(reference_elements, sirena_elements)
        reference_groups = group(reference_elements, match_by)
        sirena_groups = group(sirena_elements, match_by)

        group_results(scope, match_by, reference_groups, sirena_groups)
      end

      def in_scope(figure, scope)
        figure.elements.select { |element| scope_of(element) == scope }
      end

      def match_mode(reference_elements, sirena_elements)
        elements = reference_elements + sirena_elements
        elements.all? { |element| element.identity == :id } ? :id : :label
      end

      def group(elements, match_by)
        elements.group_by do |element|
          match_by == :id ? element.key : element.label
        end
      end

      def group_results(scope, match_by, reference_groups, sirena_groups)
        result = { pairs: [], ambiguous_count: 0, failures: [] }
        keys = (reference_groups.keys + sirena_groups.keys).uniq

        keys.each do |key|
          reference_group = reference_groups.fetch(key, [])
          sirena_group = sirena_groups.fetch(key, [])
          pairs = reference_group.zip(sirena_group).first(common_count(
            reference_group, sirena_group
          ))
          result[:pairs].concat(pairs)
          result[:ambiguous_count] += pairs.length if ambiguous?(
            reference_group, sirena_group
          )
          add_failure(result[:failures], scope, key, match_by,
                      reference_group.length, sirena_group.length)
        end

        result
      end

      def common_count(reference_group, sirena_group)
        [reference_group.length, sirena_group.length].min
      end

      def ambiguous?(reference_group, sirena_group)
        reference_group.length > 1 || sirena_group.length > 1
      end

      def add_failure(failures, scope, key, match_by, reference_count,
                      sirena_count)
        return if reference_count == sirena_count

        type = reference_count > sirena_count ? :missing : :extra
        failures << {
          type: type,
          group: [*scope, key],
          match_by: match_by,
          count: (reference_count - sirena_count).abs,
          reference_count: reference_count,
          sirena_count: sirena_count,
        }
      end

      def order_pairs(pairs)
        positions = reference.elements.each_with_index.to_h
        pairs.sort_by { |reference_element, _sirena_element| positions.fetch(reference_element) }
      end
    end
  end
end
