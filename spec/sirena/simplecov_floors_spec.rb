# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"

# .simplecov is the only place the floors live. Read it in a subprocess so a
# floor dropped or deleted there goes red here, without a COVERAGE=true run.
# These are lower bounds: raising a floor never needs an edit to this file.
RSpec.describe Sirena, ".simplecov floors" do
  let(:floors) do
    script = <<~RUBY
      require "simplecov"
      load ".simplecov"
      puts JSON.generate(SimpleCov.minimum_coverage)
    RUBY
    root = File.expand_path("../..", __dir__)
    out, status = Open3.capture2e(
      "bundle", "exec", "ruby", "-rjson", "-e", script, chdir: root
    )
    raise "reading .simplecov failed: #{out}" unless status.success?

    JSON.parse(out.lines.last)
  end

  { "line" => 97.0, "branch" => 80.0 }.each do |criterion, floor|
    it "enforces at least #{floor} #{criterion} coverage" do
      expect(floors.fetch(criterion)).to be >= floor
    end
  end
end
