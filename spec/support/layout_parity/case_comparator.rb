# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Assembles the settled per-case evidence from the extractor comparators.
    # The optional analog callable receives both SVGs and returns
    # normalized `{ key:, error: }` rows.
    class CaseComparator
      METRICS = %i[e_c e_w e_h e_a analog].freeze

      def self.compare(**arguments)
        new(arguments).compare
      end

      def initialize(arguments)
        @case_id = arguments.fetch(:case_id)
        @type = arguments.fetch(:type)
        @reference = arguments.fetch(:reference)
        @reference_svg = arguments.fetch(:reference_svg)
        @sirena_svg = arguments.fetch(:sirena_svg)
        @reproduce = arguments.fetch(:reproduce)
        @recognizer = arguments.fetch(:recognizer)
        @analog_measurements = arguments[:analog_measurements]
        @render_error = arguments[:render_error]
        @spatial_kinds = arguments.fetch(:spatial_kinds, [])
      end

      def compare
        return missing_reference_result unless reference_svg
        return render_error_result if render_error

        unless sirena_svg
          raise ArgumentError, "sirena svg or render error is required"
        end

        compare_rendered
      end

      private

      attr_reader :case_id, :type, :reference, :reference_svg, :sirena_svg,
                  :reproduce, :recognizer, :analog_measurements, :render_error,
                  :spatial_kinds

      def compare_rendered
        reference_figure, match = extract_and_match
        invariants = invariants_for(match)
        geometry = geometry_for(reference_figure, match)

        result("rendered", invariants, with_analogs(geometry))
      end

      def extract_and_match
        reference_figure = extractor.extract(reference_svg)
        sirena_figure = extractor.extract(sirena_svg)
        match = ElementMatcher.match(reference: reference_figure,
                                     sirena: sirena_figure)
        [reference_figure, match]
      end

      def invariants_for(match)
        presence_failures(match[:failures]) + spatial_failures(match[:pairs])
      end

      def extractor
        @extractor ||= SvgFigureExtractor.new(recognizer)
      end

      def presence_failures(failures)
        failures.map do |failure|
          {
            rule: "element-presence",
            subject_keys: failure[:group],
            expected: failure[:reference_count],
            actual: failure[:sirena_count],
            bbox_sirena: nil,
            bbox_reference: nil,
            normalized: {
              match_by: failure[:match_by],
              difference: failure[:type],
              count: failure[:count],
            },
          }
        end
      end

      def spatial_failures(pairs)
        selected = pairs.select do |reference_element, _sirena_element|
          spatial_kinds.include?(reference_element.kind)
        end
        SpatialInvariantChecker.check(pairs: selected)
      end

      def geometry_for(reference_figure, match)
        return empty_geometry(match[:ambiguous_count]) if match[:pairs].empty?

        GeometryComparator.compare(
          reference: reference_figure,
          pairs: match[:pairs],
          ambiguous_count: match[:ambiguous_count],
        ).merge(worst_analog: nil)
      end

      def with_analogs(geometry)
        rows = analog_rows
        worst = rows.select { |row| row[:error] }
          .max_by { |row| row[:error] }
        keys = geometry[:worst_keys].merge(analog: worst&.fetch(:key))
        geometry.merge(worst_analog: worst&.fetch(:error), worst_keys: keys)
      end

      def analog_rows
        return [] unless analog_measurements

        analog_measurements.call(
          reference_svg: reference_svg,
          sirena_svg: sirena_svg,
        ).map do |measurement|
          { key: measurement.fetch(:key), error: measurement.fetch(:error) }
        end
      end

      def missing_reference_result
        failure = {
          rule: "reference-presence",
          subject_keys: [case_id],
          expected: reference,
          actual: nil,
          bbox_sirena: nil,
          bbox_reference: nil,
          normalized: nil,
        }
        result(candidate_status, [failure], empty_geometry)
      end

      def render_error_result
        result(render_error, [], empty_geometry)
      end

      def candidate_status
        render_error || "rendered"
      end

      def empty_geometry(ambiguous = 0)
        worst_keys = METRICS.to_h { |metric| [metric, nil] }
        {
          worst_e_c: nil,
          worst_e_w: nil,
          worst_e_h: nil,
          worst_e_a: nil,
          worst_analog: nil,
          worst_keys: worst_keys,
          matched: 0,
          ambiguous: ambiguous,
          top5: [],
        }
      end

      def result(status, invariants, geometry)
        CaseResult.new(
          case_id: case_id,
          type: type,
          reference: reference,
          sirena_status: status,
          invariants: invariants,
          geometry: geometry,
          reproduce: reproduce,
        )
      end
    end
  end
end
