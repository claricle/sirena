# frozen_string_literal: true

RSpec.describe SpeedRetry do
  include SpeedRetrySandbox

  {
    "passes a :speed example that passes first time, running it once" =>
      [[:speed], 0, [1, true]],
    "passes a :speed example that fails once, running it twice" =>
      [[:speed], 1, [2, true]],
    "fails a :speed example that fails twice, running it twice" =>
      [[:speed], 2, [2, false]],
    "fails an untagged example that fails once, running it once" =>
      [[], 1, [1, false]],
  }.each do |behaviour, (tags, failures, expected)|
    it behaviour do
      outcome = run_flaky_example(tags, failures)
      expect([outcome.runs, outcome.passed]).to eq(expected)
    end
  end

  it "re-runs a :speed example under this suite's own configuration" do
    outcome = run_flaky_example([:speed], 1, suite: :real)
    expect([outcome.runs, outcome.passed]).to eq([2, true])
  end

  it "hands the running example back after a real-suite run" do |example|
    run_flaky_example([:speed], 0, suite: :real)
    handed_back = [RSpec.current_example.equal?(example), RSpec.current_scope]
    expect(handed_back).to eq([true, :example])
  end

  it "names the example and its first failure when it re-runs one" do
    expect(run_flaky_example([:speed], 1).stderr).to include(
      "a timed parse reads the clock failed once, re-running: expected: > 1",
    )
  end

  it "refuses :speed with :aggregate_failures, which would block the re-run" do
    tags = [:speed, { aggregate_failures: true }]
    outcome = run_flaky_example(tags, 0)
    expect([outcome.runs, outcome.failure])
      .to eq([0, "a :speed example cannot use :aggregate_failures"])
  end
end
