# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

# spec/spec_helper.rb's `after(:suite)` hook (registered only when
# `ENV['COVERAGE'] == 'true'` at spec_helper.rb LOAD time) is what
# lib/tasks/coverage.rake's whole changed-line gate depends on to keep
# :corpus-tagged fixture sweeps out of coverage.json -- see the comment above
# it. Nothing in this repo exercised it as a regression spec before this file
# (grepped: no reference to `RSpec.world.filtered_examples` or this hook's
# raise message anywhere else) even though its own comment calls it "the
# real guarantee" (multi-agent-review Finding 3, 2026-09-17). Because the
# hook only registers at spec_helper.rb load time, it can't be exercised by
# toggling ENV inside an in-process example the way lib/tasks/coverage.rake's
# own specs stub things -- it needs a real subprocess with COVERAGE=true set
# before spec_helper.rb loads, same as `execution-diff`'s manual experiment
# during this PR's review confirmed live.
#
# The child inherits COVERAGE=true, so it loads .simplecov and runs its own
# SimpleCov instance too -- without SIMPLECOV_COVERAGE_DIR pointed elsewhere,
# its corpus-tagged hits would merge straight into this repo's real
# coverage/.resultset.json (SimpleCov merges any resultset it finds in
# coverage_dir within merge_timeout), polluting whatever coverage:measure run
# happens to share that directory -- exactly what this guard exists to
# prevent (Codex review, 2026-09-17: reproduced real hits landing in the
# parent's coverage/coverage.json without this). Point the child at a
# throwaway directory instead and assert nothing about the real one changed --
# an earlier version of this spec unconditionally `rm_rf`'d the real
# coverage/ directory to make that assertion cheap, which destroyed a report
# `rake coverage:measure` had already generated on a real developer machine
# (Codex review round 17, 2026-09-17: reproduced with a sentinel file).
# Record its prior state (present or absent) and require it unchanged instead
# of clearing it first.
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
