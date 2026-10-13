# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"

# This hook only registers at spec_helper.rb LOAD time, so it needs a real
# subprocess with COVERAGE=true set before load -- toggling ENV in-process
# will not exercise it.
#
# The child inherits COVERAGE=true and runs its own SimpleCov instance, so
# point it at a throwaway SIMPLECOV_COVERAGE_DIR: otherwise its hits merge
# into this repo's real coverage/.resultset.json. Never `rm_rf` the real
# coverage/ directory to simplify the assertion -- that destroys a report a
# developer already generated. Record its prior state (present or absent)
# and require it unchanged instead.
RSpec.describe "spec_helper.rb corpus-tag coverage guard" do
  let(:real_coverage_dir) { File.expand_path("../coverage", __dir__) }
  let(:guard_run) do
    before = coverage_state
    result = Dir.mktmpdir("corpus-guard-spec-coverage") do |scratch_dir|
      env = { "COVERAGE" => "true", "SIMPLECOV_COVERAGE_DIR" => scratch_dir }
      Open3.capture2e(
        env, "bundle", "exec", "rspec", "--tag", "corpus",
        "spec/sirena/parser/error_spec.rb"
      )
    end
    { result: result, before: before, after: coverage_state }
  end

  let(:message) do
    Regexp.new(
      "COVERAGE=true scheduled \\d+ :corpus-tagged " \
      "example\\(s\\) to run instrumented",
    )
  end

  def coverage_state
    exists = File.exist?(real_coverage_dir)
    [exists, exists ? Dir.children(real_coverage_dir).sort : nil]
  end

  it "fails when COVERAGE=true schedules an instrumented corpus example" do
    expect(guard_run[:result].last).not_to be_success
  end

  it "explains why instrumented corpus examples cannot run" do
    expect(guard_run[:result].first).to match(message)
  end

  it "preserves the real coverage directory's presence and entries" do
    expect(guard_run[:after]).to eq(guard_run[:before])
  end
end
