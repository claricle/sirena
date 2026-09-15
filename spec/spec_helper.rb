# frozen_string_literal: true

# ENV-gated: `rake coverage:measure` sets COVERAGE=true and runs only
# `spec:unit` (the :corpus-tagged fixture sweeps are excluded there via
# lib/tasks/coverage.rake's `--tag ~corpus`), so corpus results never reach
# the coverage this starts tracking. Plain `bundle exec rspec` / `rake spec`
# still run everything, uninstrumented (SimpleCov.start never runs without
# COVERAGE=true). The `filter_run_excluding corpus:` below is the same
# exclusion enforced a SECOND way, independent of which rake task or flag
# started the process: a bare `COVERAGE=true bundle exec rspec`, with no
# `--tag` at all, would otherwise still run :corpus-tagged examples
# instrumented -- this makes "corpus results provably absent" hold for any
# invocation that sets COVERAGE=true, not only the sanctioned rake path.
# See TODO.foundation/03-coverage-gate.md item 1 and lib/tasks/coverage.rake.
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
  config.filter_run_excluding corpus: true if ENV["COVERAGE"] == "true"
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = 'doc' if config.files_to_run.one?

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end
