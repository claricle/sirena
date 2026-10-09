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
        result = aggregate(scopes.map { |scope| match_scope(scope) })

        {
          pairs: order_pairs(result[:pairs]),
          ambiguous_count: result[:ambiguous_count],
          failures: result[:failures],
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
        keys = (reference_groups.keys + sirena_groups.keys).uniq
        results = keys.map do |key|
          match_group(scope, key, match_by, reference_groups, sirena_groups)
        end
        aggregate(results)
      end

      def match_group(scope, key, match_by, reference_groups, sirena_groups)
        reference_group = reference_groups.fetch(key, [])
        sirena_group = sirena_groups.fetch(key, [])
        pairs = reference_group.zip(sirena_group).first(
          common_count(reference_group, sirena_group),
        )

        {
          pairs: pairs,
          ambiguous_count: ambiguity_count(
            reference_group, sirena_group, pairs
          ),
          failures: failure(
            scope, key, match_by, reference_group, sirena_group
          ),
        }
      end

      def common_count(reference_group, sirena_group)
        [reference_group.length, sirena_group.length].min
      end

      def ambiguous?(reference_group, sirena_group)
        reference_group.length > 1 || sirena_group.length > 1
      end

      def ambiguity_count(reference_group, sirena_group, pairs)
        ambiguous?(reference_group, sirena_group) ? pairs.length : 0
      end

      def failure(scope, key, match_by, reference_group, sirena_group)
        reference_count = reference_group.length
        sirena_count = sirena_group.length
        return [] if reference_count == sirena_count

        type = reference_count > sirena_count ? :missing : :extra
        [{
          type: type, group: [*scope, key], match_by: match_by,
          count: (reference_count - sirena_count).abs,
          reference_count: reference_count, sirena_count: sirena_count
        }]
      end

      def aggregate(results)
        results.each_with_object(empty_result) do |result, aggregate|
          aggregate[:pairs].concat(result[:pairs])
          aggregate[:ambiguous_count] += result[:ambiguous_count]
          aggregate[:failures].concat(result[:failures])
        end
      end

      def empty_result
        { pairs: [], ambiguous_count: 0, failures: [] }
      end

      def order_pairs(pairs)
        positions = reference.elements.each_with_index.to_h
        pairs.sort_by do |reference_element, _sirena_element|
          positions.fetch(reference_element)
        end
      end
    end
  end
end
