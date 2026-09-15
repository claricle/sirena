# frozen_string_literal: true

# ENV-gated: `rake coverage:measure` sets COVERAGE=true and runs only
# `spec:unit` (:corpus-tagged fixture sweeps excluded via
# lib/tasks/coverage.rake's `--tag ~corpus`); plain `bundle exec rspec` runs
# everything, uninstrumented. `filter_run_excluding corpus:` below only
# closes the bare-invocation gap -- a CLI `--tag corpus` (e.g. `rake
# spec:corpus_runner`) wins over it outright (see the gate record for the
# rspec-core mechanism). The `after(:suite)` hook below is the real
# guarantee: it checks what the filter SCHEDULED to run (not merely what it
# INTENDED to exclude), and fails loudly instead of letting corpus-inflated
# coverage.json ship silently.
if ENV["COVERAGE"] == "true"
  require "simplecov"
  SimpleCov.start
end

require "sirena"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  if ENV["COVERAGE"] == "true"
    config.filter_run_excluding corpus: true
    # Belt-and-suspenders: a CLI `--tag corpus` (e.g. `rake spec:corpus_runner`
    # called directly with COVERAGE still set) deletes the exclude rule above
    # outright -- see the comment near `SimpleCov.start`. This checks what
    # the filter SCHEDULED (RSpec.world.filtered_examples), so no filter
    # precedence trick can make it pass silently. Fail-safe, not fail-unsafe:
    # under --fail-fast a scheduled-but-never-executed corpus example can
    # still trip this (RSpec aborts before entering its group), producing a
    # false-positive raise rather than a silent miss.
    config.after(:suite) do
      scheduled = RSpec.world.filtered_examples.values.flatten.select { |e| e.metadata[:corpus] }
      next if scheduled.empty?

      raise "COVERAGE=true scheduled #{scheduled.size} :corpus-tagged example(s) to run " \
            "instrumented (#{scheduled.first.full_description.inspect} and " \
            "#{scheduled.size - 1} more) -- this would inflate coverage.json. Run without " \
            'COVERAGE, or exclude with --tag ~corpus.'
    end
  end
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = 'doc' if config.files_to_run.one?

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end
