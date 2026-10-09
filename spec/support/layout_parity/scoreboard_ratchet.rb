# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Compares fresh per-case parity rows with their committed scoreboard rows.
    class ScoreboardRatchet
      METRICS = CaseLedger::METRICS
      INFINITE_METRICS = {
        "Infinity" => Float::INFINITY,
        "-Infinity" => -Float::INFINITY,
      }.freeze

      def self.diff(committed:, fresh:)
        new(committed, fresh).diff
      end

      def initialize(committed, fresh)
        @committed = index(committed)
        @fresh = index(fresh)
      end

      def diff
        common = (committed.keys & fresh.keys).sort
        changes = common.flat_map { |case_id| changes_for(case_id) }
        {
          missing: missing_ids,
          new: new_ids,
          stale: stale_ids(common),
          regressions: changes_in(changes, :regression),
          unrecorded_improvements: changes_in(changes, :improvement),
        }
      end

      private

      attr_reader :committed, :fresh

      def missing_ids
        (committed.keys - fresh.keys).sort
      end

      def new_ids
        (fresh.keys - committed.keys).sort
      end

      def stale_ids(common)
        common.reject do |case_id|
          committed[case_id] == fresh[case_id]
        end
      end

      def changes_in(changes, direction)
        changes.select { |change| change[:direction] == direction }
          .map { |change| change.except(:direction) }
      end

      def index(rows)
        grouped = rows.group_by { |row| case_id(row) }
        duplicates = grouped.select { |_, matches| matches.size > 1 }.keys.sort
        unless duplicates.empty?
          raise ArgumentError, "duplicate case ID: #{duplicates.join(', ')}"
        end

        grouped.transform_values(&:first)
      end

      def case_id(row)
        id = row.fetch("case")
        return id if id.is_a?(String) && !id.empty?

        raise ArgumentError, "case ID must be a non-empty string"
      rescue KeyError
        raise ArgumentError, "row has no case ID"
      end

      def changes_for(case_id)
        before = committed.fetch(case_id).fetch("summary")
        after = fresh.fetch(case_id).fetch("summary")
        hard_failure_change(case_id, before, after) +
          metric_changes(case_id, before, after)
      end

      def hard_failure_change(case_id, before, after)
        previous = before.fetch("hard_failure")
        current = after.fetch("hard_failure")
        validate_boolean(previous)
        validate_boolean(current)
        return [] if previous == current

        [change(case_id, "hard_failure", previous, current,
                current ? :regression : :improvement)]
      end

      def metric_changes(case_id, before, after)
        previous = before.fetch("metrics")
        current = after.fetch("metrics")
        METRICS.filter_map do |metric|
          metric_change(case_id, metric, previous.fetch(metric),
                        current.fetch(metric))
        end
      end

      def metric_change(case_id, metric, before, after)
        previous = comparable_metric(before)
        current = comparable_metric(after)
        return unless previous && current && previous != current

        direction = current > previous ? :regression : :improvement
        change(case_id, metric, before, after, direction)
      end

      def comparable_metric(value)
        return nil if value.nil?
        return INFINITE_METRICS.fetch(value) if INFINITE_METRICS.key?(value)
        return value if finite_numeric?(value)

        raise ArgumentError, "invalid metric value: #{value.inspect}"
      end

      def finite_numeric?(value)
        value.is_a?(Numeric) && value.finite?
      end

      def validate_boolean(value)
        return if [true, false].include?(value)

        raise ArgumentError, "hard_failure must be true or false"
      end

      def change(case_id, field, before, after, direction)
        {
          case: case_id,
          field: field,
          before: before,
          after: after,
          direction: direction,
        }
      end
    end
  end
end
