# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

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
RSpec.describe 'spec_helper.rb corpus-tag coverage guard' do
  it 'raises when COVERAGE=true schedules a :corpus-tagged example instrumented, ' \
     "without touching this repo's real coverage report" do
    real_coverage_dir = File.expand_path('../coverage', __dir__)
    existed_before = File.exist?(real_coverage_dir)
    entries_before = existed_before ? Dir.children(real_coverage_dir).sort : nil

    Dir.mktmpdir('corpus-guard-spec-coverage') do |scratch_dir|
      env = { 'COVERAGE' => 'true', 'SIMPLECOV_COVERAGE_DIR' => scratch_dir }
      out, status = Open3.capture2e(
        env, 'bundle', 'exec', 'rspec', '--tag', 'corpus', 'spec/sirena/parser/error_spec.rb'
      )

      expect(status).not_to be_success
      expect(out).to match(/COVERAGE=true scheduled \d+ :corpus-tagged example\(s\) to run instrumented/)
    end

    expect(File.exist?(real_coverage_dir)).to eq(existed_before)
    expect(existed_before ? Dir.children(real_coverage_dir).sort : nil).to eq(entries_before)
  end
end
