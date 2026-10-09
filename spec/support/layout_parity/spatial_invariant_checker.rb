# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Checks containment and peer-overlap invariants for matched node pairs.
    # The caller owns node-like filtering; reference bboxes alone define
    # ancestry so Sirena geometry cannot excuse its own collisions.
    class SpatialInvariantChecker
      OVERLAP_THRESHOLD = 0.5

      def self.check(pairs:)
        new(pairs).check
      end

      def initialize(pairs)
        @pairs = pairs
        @subject_keys = build_subject_keys
      end

      def check
        failures = []
        pairs.each_index.to_a.combination(2) do |first, second|
          reference_relation = containment(first, second, side: 0)
          sirena_relation = containment(first, second, side: 1)

          add_missing_containment(failures, reference_relation,
                                  sirena_relation)
          add_unexpected_containment(failures, reference_relation,
                                     sirena_relation)
          add_peer_overlap(failures, first, second, reference_relation)
        end
        failures
      end

      private

      attr_reader :pairs, :subject_keys

      def containment(first, second, side:)
        first_box = pairs.fetch(first).fetch(side).bbox
        second_box = pairs.fetch(second).fetch(side).bbox
        return [first, second] if first_box.enclose?(second_box)
        return [second, first] if second_box.enclose?(first_box)

        nil
      end

      def add_missing_containment(failures, reference, sirena)
        return unless reference && reference != sirena

        failures << containment_evidence(
          "missing-reference-containment", reference,
          expected: true, actual: false
        )
      end

      def add_unexpected_containment(failures, reference, sirena)
        return unless sirena && reference != sirena

        failures << containment_evidence(
          "unexpected-sirena-containment", sirena,
          expected: false, actual: true
        )
      end

      def add_peer_overlap(failures, first, second, reference_relation)
        return if reference_relation

        overlap = intersection(first, second)
        return unless overlap.all? { |amount| amount > OVERLAP_THRESHOLD }

        failures << evidence(
          "peer-overlap",
          [first, second],
          expected: false,
          actual: true,
          normalized: {
            intersection_width: overlap.first,
            intersection_height: overlap.last,
            threshold: OVERLAP_THRESHOLD,
          },
        )
      end

      def containment_evidence(rule, relation, expected:, actual:)
        evidence(
          rule,
          relation,
          expected: expected,
          actual: actual,
          normalized: nil,
        )
      end

      def evidence(rule, indexes, expected:, actual:, normalized:)
        {
          rule: rule,
          subject_keys: indexes.map { |index| subject_keys.fetch(index) },
          expected: expected,
          actual: actual,
          bbox_sirena: boxes(indexes, 1),
          bbox_reference: boxes(indexes, 0),
          normalized: normalized,
        }
      end

      def boxes(indexes, side)
        indexes.map { |index| pairs.fetch(index).fetch(side).bbox.to_a }
      end

      def intersection(first, second)
        first_box = sirena_box(first)
        second_box = sirena_box(second)
        [
          horizontal_intersection(first_box, second_box),
          vertical_intersection(first_box, second_box),
        ]
      end

      def sirena_box(index)
        pairs.fetch(index).fetch(1).bbox
      end

      def horizontal_intersection(first_box, second_box)
        axis_intersection(first_box.min_x, first_box.max_x,
                          second_box.min_x, second_box.max_x)
      end

      def vertical_intersection(first_box, second_box)
        axis_intersection(first_box.min_y, first_box.max_y,
                          second_box.min_y, second_box.max_y)
      end

      def axis_intersection(first_min, first_max, second_min, second_max)
        [first_max, second_max].min - [first_min, second_min].max
      end

      def build_subject_keys
        ordinals = Hash.new(0)
        pairs.map do |reference, _sirena|
          identity = [reference.kind, reference.parent, reference.key]
          ordinal = ordinals[identity]
          ordinals[identity] += 1
          [identity, ordinal]
        end
      end
    end
  end
end
