# frozen_string_literal: true

module Sirena
  # Splits the spec files into N disjoint groups that together hold every
  # file, so CI can run the groups as parallel jobs. Selected by
  # `SIRENA_SPEC_SHARD=<index>/<count>` (1-based); unset runs everything.
  #
  # Files are dealt largest-first to the least loaded group. The weights
  # only balance the groups: a file missing from WEIGHTS still runs in
  # exactly one group, so a stale table costs speed, never coverage.
  class SpecShard
    # Seconds on a Windows runner (CI run 38054172040, Ruby 3.2); files
    # that spawn `bundle exec rubocop` or render the whole corpus.
    WEIGHTS = {
      "spec/sirena/lint_debt_spec.rb" => 178,
      "spec/sirena/lint_debt_scoreboard_spec.rb" => 164,
      "spec/scripts/corpus_sweep_task_spec.rb" => 58,
      "spec/svg_conformance_spec.rb" => 27,
      "spec/sirena/conformance_spec.rb" => 24,
      "spec/sirena/theme_spec.rb" => 11,
      "spec/sirena/parser/user_journey_spec.rb" => 11,
      "spec/sirena/notation/plant_uml_spike_spec.rb" => 10,
    }.freeze
    DEFAULT_WEIGHT = 0.6
    # Seconds the last group also spends on the non-RSpec rake tasks.
    TAIL_SECONDS = 55
    PATTERN = "spec/**{,/*/**}/*_spec.rb"

    attr_reader :index, :count

    # Returns nil when the variable is unset or empty.
    def self.from_env(env = ENV)
      value = env.fetch("SIRENA_SPEC_SHARD", "").strip
      return if value.empty?

      new(*value.split("/", 2).map { |part| Integer(part) })
    end

    def initialize(index, count)
      unless count.positive? && (1..count).cover?(index)
        raise ArgumentError, "shard #{index}/#{count} is out of range"
      end

      @index = index
      @count = count
    end

    # The last group also runs the rake tasks that follow RSpec.
    def runs_tail?
      index == count
    end

    # PATTERN matches some files twice (rspec's own default does too).
    def files(all = Dir.glob(PATTERN))
      groups(all.uniq.sort)[index - 1].sort
    end

    private

    def groups(all)
      loads = Array.new(count) { |i| i == count - 1 ? TAIL_SECONDS : 0 }
      groups = Array.new(count) { [] }
      all.sort_by { |file| [-weight(file), file] }.each do |file|
        slot = loads.index(loads.min)
        groups[slot] << file
        loads[slot] += weight(file)
      end
      groups
    end

    def weight(file)
      WEIGHTS.fetch(file, DEFAULT_WEIGHT)
    end
  end
end
