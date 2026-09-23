# frozen_string_literal: true

require 'json'
require 'open3'
require_relative '../../scripts/lane_verdict'

RSpec.describe LaneVerdict do
  describe '.failures' do
    {
      'all children succeeded' => [
        { 'unit' => { 'result' => 'success' }, 'lint' => { 'result' => 'success' } },
        []
      ],
      'a failed child' => [
        { 'unit' => { 'result' => 'success' }, 'lint' => { 'result' => 'failure' } },
        ['lint: "failure"']
      ],
      'a skipped child (dependency of a failed job)' => [
        { 'unit' => { 'result' => 'failure' }, 'docs' => { 'result' => 'skipped' } },
        ['unit: "failure"', 'docs: "skipped"']
      ],
      'a cancelled child' => [
        { 'unit' => { 'result' => 'success' }, 'lint' => { 'result' => 'cancelled' } },
        ['lint: "cancelled"']
      ],
      'no child jobs wired yet' => [
        {},
        ['no child jobs to judge']
      ]
    }.each do |label, (needs, expected)|
      it "flags #{label}" do
        expect(described_class.failures(needs)).to eq(expected)
      end
    end
  end

  describe 'as a CLI (NEEDS_JSON -> exit code)' do
    def run(needs)
      Open3.capture3(
        { 'NEEDS_JSON' => needs.to_json },
        RbConfig.ruby, File.expand_path('../../scripts/lane_verdict.rb', __dir__)
      )
    end

    it 'exits 0 and prints green when every child succeeded' do
      stdout, _stderr, status = run('unit' => { 'result' => 'success' })

      expect(stdout).to include('lane green')
      expect(status).to be_success
    end

    it 'exits nonzero when a child failed -- the aggregator must not false-green' do
      _stdout, stderr, status = run('unit' => { 'result' => 'failure' })

      expect(stderr).to include('unit: "failure"')
      expect(status).not_to be_success
    end

    it 'exits nonzero when a child was skipped -- GitHub skips dependents of a failed job' do
      _stdout, stderr, status = run('unit' => { 'result' => 'success' }, 'docs' => { 'result' => 'skipped' })

      expect(stderr).to include('docs: "skipped"')
      expect(status).not_to be_success
    end
  end
end
