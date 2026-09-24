# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'open3'
require_relative '../../scripts/ci_baseline'

RSpec.describe CiBaseline do
  describe '.resolve' do
    {
      'pull_request' => [{ 'pull_request' => { 'base' => { 'sha' => 'a' * 40 } } },
                         { mode: 'ref', ref: 'a' * 40, merge_base: true }],
      'pull_request from a fork' => [{ 'pull_request' => { 'base' => { 'sha' => 'a' * 40, 'repo' => { 'fork' => false } },
                                                           'head' => { 'repo' => { 'fork' => true } } } },
                                     { mode: 'ref', ref: 'a' * 40, merge_base: true }],
      'merge_group' => [{ 'merge_group' => { 'base_sha' => 'a' * 40 } },
                        { mode: 'ref', ref: 'a' * 40, merge_base: true }],
      'push' => [{ 'before' => 'b' * 40 }, { mode: 'ref', ref: 'b' * 40, merge_base: false }],
      'push (new branch)' => [{ 'before' => '0' * 40 }, described_class::CONSISTENCY],
      'workflow_dispatch' => [{}, described_class::CONSISTENCY],
      'schedule' => [{}, described_class::CONSISTENCY]
    }.each do |label, (payload, expected)|
      it "resolves #{label}" do
        expect(described_class.resolve(label.split.first, payload)).to eq(expected)
      end
    end

    it 'refuses an event it has no rule for' do
      expect { described_class.resolve('release', {}) }.to raise_error(ArgumentError, /release/)
    end
  end

  describe '.baseline_sha against real repositories' do
    include GitRepoHelpers

    # `CiBaseline.baseline_sha` shells out to `git fetch` itself
    # (scripts/ci_baseline.rb), so it never passes through `sh` and never sees
    # GitRepoHelpers::NO_AUTO_MAINTENANCE. That fetch spawns the detached
    # `git maintenance run` described on the constant, inside the tmpdir the
    # `after` hook below is about to delete. Production code must not carry a
    # test-only setting, so the suppression goes in the environment here instead.
    around do |example|
      restore = GitRepoHelpers::NO_AUTO_MAINTENANCE.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
      ENV.update(GitRepoHelpers::NO_AUTO_MAINTENANCE)
      example.run
    ensure
      restore.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    let(:tmp) { Dir.mktmpdir }
    let(:origin) { File.join(tmp, 'origin.git') }
    let(:shas) do
      work = File.join(tmp, 'work')
      sh(tmp, 'git', 'init', '-q', '--bare', '-b', 'main', origin)
      sh(tmp, 'git', 'clone', '-q', origin, work)
      sh(work, 'git', 'checkout', '-q', '-b', 'main')
      fork_point = commit(work, 'one')
      sh(work, 'git', 'checkout', '-q', '-b', 'topic')
      topic_tip = commit(work, 'topic')
      sh(work, 'git', 'checkout', '-q', 'main')
      base_tip = commit(work, 'two') # base moved on after the topic branched
      sh(work, 'git', 'push', '-q', 'origin', 'main', 'topic')
      { fork_point: fork_point, topic_tip: topic_tip, base_tip: base_tip }
    end

    after { FileUtils.remove_entry(tmp) }

    it 'compares a stale PR against the merge-base, not the moved base tip' do
      clone = File.join(tmp, 'full')
      shas
      sh(tmp, 'git', 'clone', '-q', origin, clone)
      sh(clone, 'git', 'checkout', '-q', '--detach', shas[:topic_tip])
      decision = { mode: 'ref', ref: shas[:base_tip], merge_base: true }
      expect(Dir.chdir(clone) { described_class.baseline_sha(decision) }).to eq(shas[:fork_point])
    end

    context 'with a shallow clone of the moved base' do
      let(:clone) { File.join(tmp, 'shallow') }

      before do
        shas
        sh(tmp, 'git', 'clone', '-q', '--depth=1', '-b', 'main', "file://#{origin}", clone)
      end

      it 'fetches a push baseline that is not in the clone yet' do
        expect(in_repo?(clone, shas[:topic_tip])).to be(false)
        decision = { mode: 'ref', ref: shas[:topic_tip], merge_base: false }
        expect(Dir.chdir(clone) { described_class.baseline_sha(decision) }).to eq(shas[:topic_tip])
        expect(in_repo?(clone, shas[:topic_tip])).to be(true)
      end

      # Guards the `around` hook above. `git fetch` is the one git write in this
      # file that CiBaseline issues itself, so this is the only place the
      # suppression can be seen working. GIT_TRACE goes to a file because
      # CiBaseline captures and discards the fetch's stderr.
      it 'does not let its own fetch spawn the detached maintenance run' do
        trace = File.join(tmp, 'trace.log')
        decision = { mode: 'ref', ref: shas[:topic_tip], merge_base: false }
        restore = ENV.fetch('GIT_TRACE', nil)
        begin
          ENV['GIT_TRACE'] = trace
          Dir.chdir(clone) { described_class.baseline_sha(decision) }
        ensure
          # Put back whatever was there, which for the usual empty case means
          # deleting. A raise here would otherwise leave GIT_TRACE set for every
          # later example in the process, and running the suite under someone's
          # own GIT_TRACE would silently unset it.
          restore.nil? ? ENV.delete('GIT_TRACE') : ENV['GIT_TRACE'] = restore
        end
        expect(File.read(trace)).not_to include('maintenance run')
      end

      it 'raises when the baseline cannot be fetched' do
        decision = { mode: 'ref', ref: 'c' * 40, merge_base: false }
        expect { Dir.chdir(clone) { described_class.baseline_sha(decision) } }.to raise_error(/git fetch/)
      end
    end

    it 'returns nil in consistency mode' do
      expect(described_class.baseline_sha(described_class::CONSISTENCY)).to be_nil
    end
  end
end
