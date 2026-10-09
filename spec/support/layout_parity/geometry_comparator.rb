# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Computes the section 3 geometry errors for already-matched elements.
    class GeometryComparator
      METRICS = %i[e_c e_w e_h e_a].freeze

      def self.compare(reference:, pairs:, ambiguous_count: 0)
        new(reference, pairs, ambiguous_count).compare
      end

      def initialize(reference, pairs, ambiguous_count)
        @reference = reference
        @pairs = pairs
        @ambiguous_count = ambiguous_count
      end

      def compare
        reference_frame = frame_for(0)
        sirena_frame = frame_for(1)
        diagonal = Math.hypot(reference_frame.width, reference_frame.height)
        translate = diagonal.positive?
        diagonal = fallback_diagonal unless translate
        rows = metric_rows(reference_frame, sirena_frame, diagonal, translate)

        result_for(rows)
      end

      private

      attr_reader :reference, :pairs, :ambiguous_count

      def frame_for(side)
        boxes = pairs.map { |pair| pair.fetch(side).bbox }
        Bbox.union(boxes) || raise(ArgumentError, "matched pairs are required")
      end

      def fallback_diagonal
        root = reference.root_box
        root_diagonal = Math.hypot(root&.width.to_f, root&.height.to_f)
        return root_diagonal if root_diagonal.positive?
        return reference.max_width if reference.max_width.to_f.positive?

        raise ArgumentError, "degenerate reference frame has no root extent"
      end

      def metric_rows(reference_frame, sirena_frame, diagonal, translate)
        pairs.each_with_index.map do |(reference_element, sirena_element), index|
          reference_box = reference_element.bbox
          sirena_box = sirena_element.bbox
          metrics = metrics_for(reference_box, sirena_box,
                                reference_frame, sirena_frame,
                                diagonal, translate)
          {
            key: element_key(reference_element),
            bbox_reference: reference_box.to_a,
            bbox_sirena: sirena_box.to_a,
            metrics: metrics,
            index: index,
          }
        end
      end

      def metrics_for(reference_box, sirena_box, reference_frame, sirena_frame,
                      diagonal, translate)
        {
          e_c: center_error(reference_box, sirena_box, reference_frame,
                            sirena_frame, diagonal, translate),
          e_w: dimension_error(reference_box.width, sirena_box.width),
          e_h: dimension_error(reference_box.height, sirena_box.height),
          e_a: aspect_error(reference_box, sirena_box),
        }
      end

      def center_error(reference_box, sirena_box, reference_frame,
                       sirena_frame, diagonal, translate)
        reference_center = normalized_center(reference_box, reference_frame,
                                             translate)
        sirena_center = normalized_center(sirena_box, sirena_frame, translate)
        Math.hypot(sirena_center[0] - reference_center[0],
                   sirena_center[1] - reference_center[1]) / diagonal
      end

      def normalized_center(box, frame, translate)
        center = box.center
        return center unless translate

        [center[0] - frame.min_x, center[1] - frame.min_y]
      end

      def dimension_error(reference_size, sirena_size)
        return nil if reference_size.zero? && sirena_size.zero?
        return Float::INFINITY if reference_size.zero?

        (sirena_size / reference_size - 1).abs
      end

      def aspect_error(reference_box, sirena_box)
        sizes = [reference_box.width, reference_box.height,
                 sirena_box.width, sirena_box.height]
        return nil if both_zero?(reference_box.width, sirena_box.width) ||
                      both_zero?(reference_box.height, sirena_box.height)
        return Float::INFINITY if sizes.any?(&:zero?)

        ((sirena_box.width / sirena_box.height) /
          (reference_box.width / reference_box.height) - 1).abs
      end

      def both_zero?(reference_size, sirena_size)
        reference_size.zero? && sirena_size.zero?
      end

      def element_key(element)
        [element.kind, element.parent, element.key]
      end

      def result_for(rows)
        worst = METRICS.to_h { |metric| [metric, worst_for(rows, metric)] }
        {
          worst_e_c: worst[:e_c]&.last,
          worst_e_w: worst[:e_w]&.last,
          worst_e_h: worst[:e_h]&.last,
          worst_e_a: worst[:e_a]&.last,
          worst_keys: worst.transform_values { |entry| entry&.first },
          matched: pairs.length,
          ambiguous: ambiguous_count,
          top5: top_five(rows),
        }
      end

      def worst_for(rows, metric)
        row = rows.select { |candidate| candidate[:metrics][metric] }
                  .max_by { |candidate| candidate[:metrics][metric] }
        [row[:key], row[:metrics][metric]] if row
      end

      def top_five(rows)
        rows.sort_by do |row|
          worst = row[:metrics].values.compact.max
          [-worst, row[:index]]
        end.first(5).map do |row|
          row.slice(:key, :bbox_sirena, :bbox_reference)
        end
      end
    end
  end
end
