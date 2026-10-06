# frozen_string_literal: true

require "rspec/core/sandbox"
require "stringio"

# Runs a one-example group, either in a sandboxed RSpec whose only
# configuration is SpeedRetry (suite: :sandbox) or under this suite's own
# configuration (suite: :real). What it printed to stderr is captured.
module SpeedRetrySandbox
  Outcome = Struct.new(:runs, :passed, :failure, :stderr, keyword_init: true)

  # The example fails its first `failures` runs. It counts runs through a
  # `let`, so a re-run that kept the old memoized value would fail again.
  def run_flaky_example(tags, failures, suite: :sandbox)
    runs = 0 # rubocop:disable RSpec/LeakyLocalVariable -- the only channel out of the inner example
    outcome = run_example(tags, suite:) do
      let(:attempt) { runs += 1 }

      it("reads the clock") { expect(attempt).to be > failures }
    end
    outcome.runs = runs
    outcome
  end

  # An example that reads `clock`, a method the `helpers` module provides.
  def run_clock_read(tags, helpers, clock)
    run_example(tags) do
      include helpers

      it("reads the clock") do
        expect(public_send(clock) { nil }).to be_a(Float)
      end
    end
  end

  def run_example(tags, suite: :sandbox, &body)
    outer = [$stderr, RSpec.current_example, RSpec.current_scope]
    $stderr = StringIO.new
    group, passed = run_group(tags, suite, &body)
    failure = group.examples.first.exception&.message
    Outcome.new(passed:, failure:, stderr: $stderr.string)
  ensure
    # The inner run clears the current example and scope, and wall_time
    # would then refuse the outer example.
    $stderr, RSpec.current_example, RSpec.current_scope = outer
  end

  private

  def run_group(tags, suite, &)
    return run_sandboxed_group(tags, &) if suite == :sandbox

    group = RSpec.describe("a timed parse", *tags, &)
    RSpec.world.example_groups.delete(group)
    [group, group.run]
  end

  def run_sandboxed_group(tags, &body)
    group = nil
    passed = RSpec::Core::Sandbox.sandboxed do |config|
      SpeedRetry.install(config)
      group = RSpec.describe("a timed parse", *tags, &body)
      group.run
    end
    [group, passed]
  end
end
