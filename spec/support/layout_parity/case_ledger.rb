# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Materializes deterministic, JSON-safe scoreboard rows from case results.
    class CaseLedger
      METRICS = %w[
        worst_e_c
        worst_e_w
        worst_e_h
        worst_e_a
        worst_analog
      ].freeze
      JSON_SCALARS = [String, Integer, TrueClass, FalseClass, NilClass].freeze
      # Suppress runtime noise far below the 0.08 and 0.15 contract thresholds.
      SCOREBOARD_DECIMAL_PLACES = 12

      def self.build(results)
        new(results).build
      end

      def initialize(results)
        @results = results
      end

      def build
        rows = results.map { |result| row_for(result) }
        reject_duplicate_ids(rows)
        rows.sort_by { |row| row.fetch("case") }
      end

      private

      attr_reader :results

      def row_for(result)
        evidence = json_value(result.to_h)
        case_id = evidence.fetch("case")
        validate_case_id(case_id)
        geometry = evidence.fetch("geometry")
        metrics = METRICS.to_h do |metric|
          value = normalized_metric(geometry.fetch(metric))
          geometry[metric] = value
          [metric, value]
        end

        evidence.merge(
          "summary" => {
            "hard_failure" => result.hard_failure?,
            "metrics" => metrics,
          },
        )
      end

      def validate_case_id(case_id)
        return if case_id.is_a?(String) && !case_id.empty?

        raise ArgumentError, "case ID must be a non-empty string"
      end

      def reject_duplicate_ids(rows)
        duplicates = rows.map { |row| row.fetch("case") }
          .tally.select { |_, count| count > 1 }.keys.sort
        return if duplicates.empty?

        raise ArgumentError, "duplicate case ID: #{duplicates.join(', ')}"
      end

      def json_value(value)
        return json_collection(value) if value.is_a?(Hash) || value.is_a?(Array)

        json_scalar(value)
      end

      def json_scalar(value)
        return value.to_s if value.is_a?(Symbol)
        return value if JSON_SCALARS.any? { |type| value.is_a?(type) }
        return json_float(value) if value.is_a?(Float)

        raise ArgumentError, "#{value.class} is not a JSON value"
      end

      def json_collection(value)
        return json_hash(value) if value.is_a?(Hash)

        value.map { |item| json_value(item) }
      end

      def json_hash(value)
        normalized = {}
        value.sort_by { |key, _| key.to_s }.each do |key, item|
          string_key = json_key(key)
          if normalized.key?(string_key)
            raise ArgumentError, "duplicate JSON key: #{string_key}"
          end

          normalized[string_key] = json_value(item)
        end
        normalized
      end

      def json_key(key)
        return key.to_s if key.is_a?(String) || key.is_a?(Symbol)

        raise ArgumentError, "#{key.class} is not a JSON object key"
      end

      def json_float(value)
        return value if value.finite?
        return "Infinity" if value.infinite? == 1
        return "-Infinity" if value.infinite? == -1

        raise ArgumentError, "NaN is not a JSON value"
      end

      def normalized_metric(value)
        return value unless value.is_a?(Float) && value.finite?

        rounded = value.round(SCOREBOARD_DECIMAL_PLACES)
        rounded.zero? ? 0.0 : rounded
      end
    end
  end
end
