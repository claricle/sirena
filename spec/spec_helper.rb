# frozen_string_literal: true

# ENV-gated: `rake coverage:measure` sets COVERAGE=true and runs only
# `spec:unit` (the :corpus-tagged fixture sweeps are excluded there via
# lib/tasks/coverage.rake's `--tag ~corpus`), so corpus results never reach
# the coverage this starts tracking. Plain `bundle exec rspec` / `rake spec`
# still run everything, uninstrumented (SimpleCov.start never runs without
# COVERAGE=true).
#
# `filter_run_excluding corpus:` below closes the bare-invocation gap (a
# `COVERAGE=true bundle exec rspec` with no `--tag` at all would otherwise
# still run :corpus-tagged examples instrumented) -- but it does NOT close
# `COVERAGE=true bundle exec rspec --tag corpus` or `... rake
# spec:corpus_runner`: RSpec::Core::ConfigurationOptions applies a CLI
# `--tag` INCLUDE after this config-level EXCLUDE runs, and
# FilterManager#add deletes the losing rule from the other side entirely
# (rspec-core 3.13.6, filter_manager.rb) -- the CLI flag wins outright, not
# merely overrides for that run. So the `after(:suite)` hook below is the
# real guarantee: it inspects what actually ran, not what any filter
# INTENDED to exclude, and fails loudly rather than let a corpus-inflated
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
    # RAN, so no filter precedence trick can make it pass silently.
    config.after(:suite) do
      ran = RSpec.world.filtered_examples.values.flatten.select { |e| e.metadata[:corpus] }
      next if ran.empty?

      raise "COVERAGE=true ran #{ran.size} :corpus-tagged example(s) instrumented " \
            "(#{ran.first.full_description.inspect} and #{ran.size - 1} more) -- this " \
            'would inflate coverage.json. Run without COVERAGE, or exclude with --tag ~corpus.'
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
