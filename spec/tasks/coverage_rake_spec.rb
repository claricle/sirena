# frozen_string_literal: true

require 'spec_helper'
require 'rake'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'

# tasks/coverage.rake is loaded only by the Rakefile (`Dir.glob('tasks/**/*.rake')`),
# never required by the app itself, so nothing in spec/sirena/** exercises it -- mutation-check.sh
# and line-deletion-check.sh both confirmed 0% protection for this file before this spec existed.
# Each example gets its OWN Rake::Application: a Rake::Task only ever runs once per
# application (`invoke` is a no-op once marked complete), and several examples below
# `clear`/redefine `spec:unit`/`spec:corpus_runner` to observe what coverage:measure/
# spec:corpus pass them -- reusing this process's real, shared Rake.application would leak
# that invoked/redefined state across examples and could disturb whatever actually invoked
# this spec run. Each example also gets its own throwaway git repo, so
# `coverage:changed_lines`'s `git diff --merge-base` / `git ls-files` calls have something real
# to run against without touching this repo's own history or coverage/ directory.
RSpec.describe 'tasks/coverage.rake' do
  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    load File.expand_path('../../tasks/coverage.rake', __dir__)

    Dir.mktmpdir('coverage-rake-spec') do |dir|
      Dir.chdir(dir) { example.run }
    end
  ensure
    Rake.application = original_application
  end

  include GitRepoHelpers

  # Goes through GitRepoHelpers#sh rather than running its own git, so the
  # NO_AUTO_MAINTENANCE suppression that stops the detached `git maintenance
  # run` racing this example's `Dir.mktmpdir` teardown has ONE call site -- the
  # one spec/git_repo_helpers_spec.rb asserts. A second copy here would be a
  # second thing to forget. The `around` hook above has already chdir'd into
  # the throwaway repo, so Dir.pwd is it.
  def run_git!(*args)
    sh(Dir.pwd, 'git', *args)
  end

  def init_repo!
    run_git! 'init', '-q', '-b', 'main'
    run_git! 'config', 'user.email', 'coverage-rake-spec@example.com'
    run_git! 'config', 'user.name', 'coverage-rake-spec'
  end

  def commit!(path, content)
    FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == '.'
    File.write(path, content)
    run_git! 'add', path
    run_git! 'commit', '-q', '-m', "commit #{path}"
  end

  def head_sha
    out, _err, status = Open3.capture3('git', 'rev-parse', 'HEAD')
    raise 'git rev-parse HEAD failed' unless status.success?

    out.strip
  end

  around do |example|
    previous_base = ENV.fetch('COVERAGE_BASE', nil)
    example.run
  ensure
    ENV['COVERAGE_BASE'] = previous_base
  end

  around do |example|
    previous_coverage = ENV.fetch('COVERAGE', nil)
    example.run
  ensure
    ENV['COVERAGE'] = previous_coverage
  end

  describe 'coverage:changed_lines' do
    subject(:invoke!) { Rake::Task['coverage:changed_lines'].invoke }

    # The task's `sh 'bundle', 'exec', 'simplecov', 'patch', ...` call (line
    # 168-169 of coverage.rake) executes in the task block's own binding,
    # which -- since coverage.rake is loaded via plain `load` (no `wrap:`),
    # not `require` -- is the process's single top-level `main` object, not
    # this example group. Stubbing `sh` there lets an example assert the
    # call's real argv without spawning `bundle exec simplecov patch` for
    # real every time (verified against `TOPLEVEL_BINDING.receiver.equal?`
    # the block's own `binding.receiver` before relying on this).
    def main_object
      TOPLEVEL_BINDING.receiver
    end

    def stub_sh!
      allow(main_object).to receive(:sh)
    end

    # Asserts the exact argv the real `sh` call in coverage.rake is supposed
    # to pass -- not just that guards upstream didn't raise. Checking only
    # "no known guard-message raised" stays green even with the `sh` call
    # deleted entirely or its `--minimum` dropped to `0`.
    def expect_sh_invoked_for_gate!(base)
      expect(main_object).to have_received(:sh).with(
        'bundle', 'exec', 'simplecov', 'patch', '--input', 'tmp/coverage-line-only.json',
        '--base', base, '--find-renames', '--minimum', '100'
      )
    end

    it 'raises before touching git when COVERAGE_BASE looks like an option' do
      init_repo!
      ENV['COVERAGE_BASE'] = '--upstream'

      expect { invoke! }.to raise_error(/looks like an option, not a ref/)
    end

    it 'raises when coverage/coverage.json does not exist yet' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      ENV['COVERAGE_BASE'] = 'HEAD'

      expect { invoke! }.to raise_error(%r{coverage/coverage\.json is missing.*rake coverage:measure.*rake coverage:guard.*coverage:changed_lines}m)
    end

    it 'raises with the git failure when COVERAGE_BASE does not resolve to a ref' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      FileUtils.mkdir_p('coverage')
      File.write('coverage/coverage.json', JSON.generate('coverage' => {}))
      ENV['COVERAGE_BASE'] = 'this-ref-does-not-exist'

      expect { invoke! }.to raise_error(/git diff --name-only --merge-base this-ref-does-not-exist failed/)
    end

    it 'raises when a changed file was edited after the report was generated (stale mtime)' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      base = head_sha
      commit!('lib/foo.rb', "class Foo\n  def bar; end\nend\n")

      FileUtils.mkdir_p('coverage')
      File.write('coverage/coverage.json', JSON.generate('coverage' => {}))
      long_ago = Time.now - 3600
      File.utime(long_ago, long_ago, 'coverage/coverage.json')
      File.utime(Time.now, Time.now, 'lib/foo.rb')
      ENV['COVERAGE_BASE'] = base

      expect { invoke! }.to raise_error(/predates a newer edit to lib\/foo\.rb.*run `rake coverage:measure` again before coverage:changed_lines/)
    end

    it 'raises when the report has no entry at all for a changed lib/*.rb file' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      base = head_sha
      commit!('lib/foo.rb', "class Foo\n  def bar; end\nend\n")

      FileUtils.mkdir_p('coverage')
      File.write('coverage/coverage.json', JSON.generate('coverage' => {}))
      long_ago = Time.now - 3600
      File.utime(long_ago, long_ago, 'lib/foo.rb')
      File.utime(Time.now, Time.now, 'coverage/coverage.json')
      ENV['COVERAGE_BASE'] = base

      expect { invoke! }.to raise_error(/no entry \(or a content mismatch.*for lib\/foo\.rb.*run `rake coverage:measure` again before.*coverage:changed_lines/m)
    end

    it 'raises when the report entry is present but its source content is stale (same length, different text)' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      base = head_sha
      commit!('lib/foo.rb', "class Bar\nend\n") # same 2 lines, different content than the report below

      FileUtils.mkdir_p('coverage')
      report = {
        'coverage' => {
          'lib/foo.rb' => { 'source' => ['class Foo', 'end'], 'lines' => [1, nil] }
        }
      }
      File.write('coverage/coverage.json', JSON.generate(report))
      long_ago = Time.now - 3600
      File.utime(long_ago, long_ago, 'lib/foo.rb')
      File.utime(Time.now, Time.now, 'coverage/coverage.json')
      ENV['COVERAGE_BASE'] = base

      expect { invoke! }.to raise_error(/no entry \(or a content mismatch.*for lib\/foo\.rb.*run `rake coverage:measure` again before.*coverage:changed_lines/m)
    end

    it 'ignores a changed file outside lib/ or not ending in .rb -- no report entry required' do
      init_repo!
      commit!('README.md', "# hello\n")
      base = head_sha
      commit!('README.md', "# hello again\n")

      FileUtils.mkdir_p('coverage')
      File.write('coverage/coverage.json', JSON.generate('coverage' => {}))
      long_ago = Time.now - 3600
      File.utime(long_ago, long_ago, 'README.md')
      File.utime(Time.now, Time.now, 'coverage/coverage.json')
      ENV['COVERAGE_BASE'] = base
      stub_sh!

      # README.md is exempt from the report-entry check, so every fail-closed
      # guard passes and the task reaches the real gate call.
      expect { invoke! }.not_to raise_error
      expect_sh_invoked_for_gate!(base)
    end

    it 'requires a report entry only when a changed path matches BOTH halves of lib/*.rb (guards against && degrading to ||)' do
      init_repo!
      commit!('lib/foo.txt', "hello\n")
      base = head_sha
      commit!('lib/foo.txt', "hello again\n")

      FileUtils.mkdir_p('coverage')
      # No report entry for lib/foo.txt -- if the `&&` at coverage.rake:150
      # degraded to `||`, this path (starts_with lib/, but not .rb) would
      # start requiring one and raise "no entry".
      File.write('coverage/coverage.json', JSON.generate('coverage' => {}))
      long_ago = Time.now - 3600
      File.utime(long_ago, long_ago, 'lib/foo.txt')
      File.utime(Time.now, Time.now, 'coverage/coverage.json')
      ENV['COVERAGE_BASE'] = base
      stub_sh!

      expect { invoke! }.not_to raise_error
      expect_sh_invoked_for_gate!(base)
    end

    it 'skips a deleted lib/*.rb file for both the mtime and content-entry checks -- simplecov patch --find-renames handles it' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      base = head_sha
      run_git! 'rm', '-q', 'lib/foo.rb'
      run_git! 'commit', '-q', '-m', 'delete lib/foo.rb'

      FileUtils.mkdir_p('coverage')
      # No entry for lib/foo.rb at all, and no way to set its mtime (it no
      # longer exists) -- if either fail-closed check did not skip a missing
      # file, this would raise instead of reaching the gate call below.
      File.write('coverage/coverage.json', JSON.generate('coverage' => {}))
      ENV['COVERAGE_BASE'] = base
      stub_sh!

      expect { invoke! }.not_to raise_error
      expect_sh_invoked_for_gate!(base)
    end

    it 'raises when a changed non-lib file (e.g. its only covering spec) was deleted -- ' \
       'the old report can no longer prove what ran against a lib/*.rb file it still covers' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      commit!('spec/foo_spec.rb', "RSpec.describe('Foo') { it { } }\n")
      base = head_sha
      run_git! 'rm', '-q', 'spec/foo_spec.rb'
      run_git! 'commit', '-q', '-m', 'delete spec/foo_spec.rb'

      source_lines = File.readlines('lib/foo.rb', chomp: true)
      FileUtils.mkdir_p('coverage')
      report = {
        'coverage' => {
          'lib/foo.rb' => { 'source' => source_lines, 'lines' => Array.new(source_lines.size, 1) }
        }
      }
      File.write('coverage/coverage.json', JSON.generate(report))
      long_ago = Time.now - 3600
      File.utime(long_ago, long_ago, 'lib/foo.rb')
      File.utime(Time.now, Time.now, 'coverage/coverage.json')
      ENV['COVERAGE_BASE'] = base
      stub_sh!

      expect { invoke! }.to raise_error(/spec\/foo_spec\.rb deleted vs COVERAGE_BASE=#{Regexp.escape(base.inspect)}.*Move COVERAGE_BASE past this deletion instead/m)
      expect(main_object).not_to have_received(:sh)
    end

    it 're-running coverage:measure does NOT clear the deleted-non-lib guard -- only moving COVERAGE_BASE does' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      commit!('spec/foo_spec.rb', "RSpec.describe('Foo') { it { } }\n")
      old_base = head_sha
      run_git! 'rm', '-q', 'spec/foo_spec.rb'
      run_git! 'commit', '-q', '-m', 'delete spec/foo_spec.rb'
      new_base = head_sha

      source_lines = File.readlines('lib/foo.rb', chomp: true)
      FileUtils.mkdir_p('coverage')
      # A freshly generated report (current mtime, matching source) -- exactly what
      # re-running `rake coverage:measure` produces -- still cannot satisfy this guard
      # against old_base, because the guard has no freshness dimension.
      report = {
        'coverage' => {
          'lib/foo.rb' => { 'source' => source_lines, 'lines' => Array.new(source_lines.size, 1) }
        }
      }
      File.write('coverage/coverage.json', JSON.generate(report))
      ENV['COVERAGE_BASE'] = old_base
      stub_sh!

      expect { invoke! }.to raise_error(/Move COVERAGE_BASE past this deletion instead/)

      # invoke! is a memoized subject -- call the task directly for the second
      # invocation, and reenable first since a Rake::Task only runs once per
      # application.
      Rake::Task['coverage:changed_lines'].reenable
      ENV['COVERAGE_BASE'] = new_base
      expect { Rake::Task['coverage:changed_lines'].invoke }.not_to raise_error
    end

    it 'passes every fail-closed guard and reaches the real simplecov patch subprocess when the report is fresh and matches' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      base = head_sha
      commit!('lib/foo.rb', "class Foo\n  def bar; end\nend\n")

      source_lines = File.readlines('lib/foo.rb', chomp: true)
      FileUtils.mkdir_p('coverage')
      report = {
        'coverage' => {
          'lib/foo.rb' => {
            'source' => source_lines,
            'lines' => Array.new(source_lines.size, 1),
            'branches' => {},
            'methods' => {}
          }
        }
      }
      File.write('coverage/coverage.json', JSON.generate(report))
      long_ago = Time.now - 3600
      File.utime(long_ago, long_ago, 'lib/foo.rb')
      File.utime(Time.now, Time.now, 'coverage/coverage.json')
      ENV['COVERAGE_BASE'] = base
      stub_sh!

      expect { invoke! }.not_to raise_error
      expect_sh_invoked_for_gate!(base)
      # tmp/coverage-line-only.json is only written after every guard above passes.
      expect(File).to exist('tmp/coverage-line-only.json')
      written = JSON.parse(File.read('tmp/coverage-line-only.json'))
      expect(written['coverage']['lib/foo.rb']).not_to have_key('branches')
      expect(written['coverage']['lib/foo.rb']).not_to have_key('methods')
    end

    it 'refuses to read coverage/coverage.json through a symlink' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      base = head_sha

      FileUtils.mkdir_p('coverage')
      File.write('../outside-target.json', JSON.generate('coverage' => {}))
      File.symlink(File.expand_path('../outside-target.json'), 'coverage/coverage.json')
      ENV['COVERAGE_BASE'] = base

      expect { invoke! }.to raise_error(/coverage\/coverage\.json is a symlink -- refusing to read through it/)
    end

    it 'does not follow a symlink left at tmp/coverage-line-only.json -- clears it and writes a real file instead' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      base = head_sha
      commit!('lib/foo.rb', "class Foo\n  def bar; end\nend\n")

      source_lines = File.readlines('lib/foo.rb', chomp: true)
      FileUtils.mkdir_p('coverage')
      report = {
        'coverage' => {
          'lib/foo.rb' => { 'source' => source_lines, 'lines' => Array.new(source_lines.size, 1) }
        }
      }
      File.write('coverage/coverage.json', JSON.generate(report))
      long_ago = Time.now - 3600
      File.utime(long_ago, long_ago, 'lib/foo.rb')

      # Create the symlink BEFORE touching coverage.json's mtime below: it is an
      # untracked path, so `git ls-files --others --exclude-standard` puts it in
      # changed_paths, and the staleness guard (coverage.rake:133) would otherwise
      # see it as newer than the report and raise before this test ever reaches
      # the symlink-write guard it means to exercise.
      FileUtils.mkdir_p('tmp')
      File.write('../outside-victim.txt', 'untouched')
      File.symlink(File.expand_path('../outside-victim.txt'), 'tmp/coverage-line-only.json')

      File.utime(Time.now, Time.now, 'coverage/coverage.json')
      ENV['COVERAGE_BASE'] = base
      stub_sh!

      expect { invoke! }.not_to raise_error
      expect(File.symlink?('tmp/coverage-line-only.json')).to be(false)
      expect(File.read('../outside-victim.txt')).to eq('untouched')
    end

    it 'requires a report entry for a brand-new lib/*.rb file that was never `git add`ed' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      base = head_sha

      FileUtils.mkdir_p('lib')
      File.write('lib/untracked.rb', "class Untracked\nend\n") # deliberately never committed or added

      FileUtils.mkdir_p('coverage')
      File.write('coverage/coverage.json', JSON.generate('coverage' => {}))
      long_ago = Time.now - 3600
      File.utime(long_ago, long_ago, 'lib/untracked.rb')
      File.utime(Time.now, Time.now, 'coverage/coverage.json')
      ENV['COVERAGE_BASE'] = base
      stub_sh!

      expect { invoke! }.to raise_error(/no entry \(or a content mismatch.*for lib\/untracked\.rb/m)
      expect(main_object).not_to have_received(:sh)
    end

    it 'catches a gutted non-lib file with a backdated mtime, via the manifest coverage:measure writes' do
      init_repo!
      commit!('lib/foo.rb', "class Foo\nend\n")
      commit!('spec/foo_spec.rb', "RSpec.describe(Foo) { it('real') { expect(Foo.new).to be_a(Foo) } }\n")
      base = head_sha
      commit!('lib/foo.rb', "class Foo\n  def bar; end\nend\n")

      source_lines = File.readlines('lib/foo.rb', chomp: true)
      FileUtils.mkdir_p('coverage')
      File.write('coverage/coverage.json', JSON.generate(
                                             'coverage' => { 'lib/foo.rb' => { 'source' => source_lines, 'lines' => Array.new(source_lines.size, 1) } }
                                           ))

      # Run the REAL coverage:measure task (spec:unit itself stubbed to a
      # no-op -- this spec is about the manifest measure writes, not about
      # actually re-running the suite) so it snapshots spec/foo_spec.rb's
      # real, un-gutted content into tmp/coverage-source-manifest.json.
      Rake::Task['spec:unit'].clear
      Rake::Task.define_task('spec:unit') { nil }
      Rake::Task['coverage:measure'].invoke

      # Now gut the spec that alone exercised lib/foo.rb, and backdate its
      # mtime ahead of coverage.json's -- the mtime-only guard above would
      # let this through silently; only the manifest's content hash catches it.
      File.write('spec/foo_spec.rb', "RSpec.describe(Foo) {}\n")
      long_ago = Time.now - 3600
      File.utime(long_ago, long_ago, 'spec/foo_spec.rb')
      File.utime(Time.now, Time.now, 'coverage/coverage.json', 'lib/foo.rb')
      ENV['COVERAGE_BASE'] = base
      stub_sh!

      expect { invoke! }.to raise_error(/predates a newer edit to spec\/foo_spec\.rb.*coverage:measure-time snapshot.*run `rake coverage:measure` again/m)
      expect(main_object).not_to have_received(:sh)
    end

    # No stub_sh!: this runs the real `bundle exec simplecov patch`, so the
    # --minimum 100 argument is what decides pass or fail. The temp repo has
    # no Gemfile of its own, so BUNDLE_GEMFILE points at this repo's -- else
    # `bundle exec` would fail for the wrong reason and the red case would
    # pass without proving anything.
    describe 'through the real simplecov patch entry point' do
      subject(:gate) do
        init_repo!
        commit!('lib/foo.rb', "class Foo\nend\n")
        base = head_sha
        commit!('lib/foo.rb', "class Foo\n  def bar\n    1\n  end\nend\n")

        source_lines = File.readlines('lib/foo.rb', chomp: true)
        FileUtils.mkdir_p('coverage')
        File.write('coverage/coverage.json', JSON.generate(
                                               'coverage' => { 'lib/foo.rb' => { 'source' => source_lines, 'lines' => [1, 1, hits, 1, 1] } }
                                             ))
        File.utime(Time.now, Time.now, 'coverage/coverage.json')
        ENV['COVERAGE_BASE'] = base
        Rake::Task['coverage:changed_lines'].invoke
      end

      around do |example|
        previous_gemfile = ENV.fetch('BUNDLE_GEMFILE', nil)
        ENV['BUNDLE_GEMFILE'] = File.expand_path('../../Gemfile', __dir__)
        example.run
      ensure
        ENV['BUNDLE_GEMFILE'] = previous_gemfile
      end

      let(:hits) { |example| example.metadata.fetch(:hits) }

      it 'exits non-zero when a changed lib line has no coverage', hits: 0 do
        expect { gate }.to raise_error(/Command failed with status \(1\)/)
      end

      it 'passes when every changed lib line is covered', hits: 1 do
        expect { gate }.not_to raise_error
      end
    end
  end

  describe 'coverage:measure' do
    it 'sets COVERAGE=true for spec:unit and restores the previous value even when spec:unit raises' do
      ENV.delete('COVERAGE')

      seen_coverage = nil
      Rake::Task['spec:unit'].clear
      Rake::Task.define_task('spec:unit') do
        seen_coverage = ENV.fetch('COVERAGE', nil)
        raise 'spec:unit boom'
      end

      expect { Rake::Task['coverage:measure'].invoke }.to raise_error('spec:unit boom')
      expect(seen_coverage).to eq('true')
      expect(ENV.fetch('COVERAGE', nil)).to be_nil
    end

    it 'restores a previously-set COVERAGE value rather than clearing it' do
      ENV['COVERAGE'] = 'was-already-set'

      Rake::Task['spec:unit'].clear
      Rake::Task.define_task('spec:unit') { nil } # stand in for the real spec run

      Rake::Task['coverage:measure'].invoke
      expect(ENV.fetch('COVERAGE', nil)).to eq('was-already-set')
    end

    it 'reenables spec:unit so a second invocation in the same process actually reruns it' do
      ENV.delete('COVERAGE')

      invocations = 0
      Rake::Task['spec:unit'].clear
      Rake::Task.define_task('spec:unit') { invocations += 1 }

      Rake::Task['coverage:measure'].invoke
      Rake::Task['coverage:measure'].reenable
      Rake::Task['coverage:measure'].invoke

      expect(invocations).to eq(2)
    end
  end

  describe 'spec:corpus' do
    it 'clears COVERAGE for spec:corpus_runner and restores the previous value even when it raises' do
      ENV['COVERAGE'] = 'true'

      seen_coverage = :unset
      Rake::Task['spec:corpus_runner'].clear
      Rake::Task.define_task('spec:corpus_runner') do
        seen_coverage = ENV.fetch('COVERAGE', nil)
        raise 'spec:corpus_runner boom'
      end

      expect { Rake::Task['spec:corpus'].invoke }.to raise_error('spec:corpus_runner boom')
      expect(seen_coverage).to be_nil
      expect(ENV.fetch('COVERAGE', nil)).to eq('true')
    end

    it 'reenables spec:corpus_runner so a second invocation in the same process actually reruns it' do
      ENV.delete('COVERAGE')

      invocations = 0
      Rake::Task['spec:corpus_runner'].clear
      Rake::Task.define_task('spec:corpus_runner') { invocations += 1 }

      Rake::Task['spec:corpus'].invoke
      Rake::Task['spec:corpus'].reenable
      Rake::Task['spec:corpus'].invoke

      expect(invocations).to eq(2)
    end
  end

  describe 'coverage:guard' do
    it 'chains measure then changed_lines, in that order' do
      order = []
      Rake::Task['coverage:measure'].clear
      Rake::Task.define_task('coverage:measure') { order << :measure }
      Rake::Task['coverage:changed_lines'].clear
      Rake::Task.define_task('coverage:changed_lines') { order << :changed_lines }

      Rake::Task['coverage:guard'].invoke
      expect(order).to eq([:measure, :changed_lines])
    end
  end
end
