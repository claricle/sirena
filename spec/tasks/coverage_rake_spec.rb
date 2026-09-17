# frozen_string_literal: true

require 'spec_helper'
require 'rake'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'

# lib/tasks/coverage.rake is loaded only by the Rakefile (`Dir.glob('lib/tasks/**/*.rake')`),
# never required by the app itself, so nothing in spec/sirena/** exercises it -- mutation-check.sh
# and line-deletion-check.sh both confirmed 0% protection for this file before this spec existed.
# Each example gets its OWN Rake::Application (the real one is unusable here: `rake` already
# invoked `spec:unit`, which is this very process) and its own throwaway git repo, so
# `coverage:changed_lines`'s `git diff --merge-base` / `git ls-files` calls have something real
# to run against without touching this repo's own history or coverage/ directory.
RSpec.describe 'lib/tasks/coverage.rake' do
  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    load File.expand_path('../../lib/tasks/coverage.rake', __dir__)

    Dir.mktmpdir('coverage-rake-spec') do |dir|
      Dir.chdir(dir) { example.run }
    end
  ensure
    Rake.application = original_application
  end

  def run_git!(*args)
    _out, err, status = Open3.capture3('git', *args)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?
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

  describe 'coverage:changed_lines' do
    subject(:invoke!) { Rake::Task['coverage:changed_lines'].invoke }

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

      # Passes every fail-closed guard (README.md is exempt) and reaches the
      # real `sh` call, which then fails for its own reasons (no gemfile-local
      # simplecov project state / nothing to patch) -- assert we got THAT far
      # by checking none of this task's own guard messages fired.
      error = nil
      begin
        invoke!
      rescue StandardError => e
        error = e
      end
      guard_messages = [
        /looks like an option/, %r{coverage/coverage\.json is missing}, /git diff --name-only/,
        /git ls-files/, /predates a newer edit/, /no entry \(or a content mismatch/
      ]
      guard_messages.each { |pattern| expect(error&.message.to_s).not_to match(pattern) }
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
      # file, this would raise.
      File.write('coverage/coverage.json', JSON.generate('coverage' => {}))
      ENV['COVERAGE_BASE'] = base

      error = nil
      begin
        invoke!
      rescue StandardError => e
        error = e
      end
      guard_messages = [
        /looks like an option/, %r{coverage/coverage\.json is missing}, /git diff --name-only/,
        /git ls-files/, /predates a newer edit/, /no entry \(or a content mismatch/
      ]
      guard_messages.each { |pattern| expect(error&.message.to_s).not_to match(pattern) }
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

      error = nil
      begin
        invoke!
      rescue StandardError => e
        error = e
      end
      guard_messages = [
        /looks like an option/, %r{coverage/coverage\.json is missing}, /git diff --name-only/,
        /git ls-files/, /predates a newer edit/, /no entry \(or a content mismatch/
      ]
      guard_messages.each { |pattern| expect(error&.message.to_s).not_to match(pattern) }
      # tmp/coverage-line-only.json is only written after every guard above passes.
      expect(File).to exist('tmp/coverage-line-only.json')
      written = JSON.parse(File.read('tmp/coverage-line-only.json'))
      expect(written['coverage']['lib/foo.rb']).not_to have_key('branches')
      expect(written['coverage']['lib/foo.rb']).not_to have_key('methods')
    end
  end

  describe 'coverage:measure' do
    it 'sets COVERAGE=true for spec:unit and restores the previous value even when spec:unit raises' do
      init_repo!
      previous_coverage = ENV.fetch('COVERAGE', nil)
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
    ensure
      ENV['COVERAGE'] = previous_coverage
    end

    it 'restores a previously-set COVERAGE value rather than clearing it' do
      init_repo!
      previous_coverage = ENV.fetch('COVERAGE', nil)
      ENV['COVERAGE'] = 'was-already-set'

      Rake::Task['spec:unit'].clear
      Rake::Task.define_task('spec:unit') { nil } # stand in for the real spec run

      Rake::Task['coverage:measure'].invoke
      expect(ENV.fetch('COVERAGE', nil)).to eq('was-already-set')
    ensure
      ENV['COVERAGE'] = previous_coverage
    end

    it 'reenables spec:unit so a second invocation in the same process actually reruns it' do
      init_repo!
      previous_coverage = ENV.fetch('COVERAGE', nil)
      ENV.delete('COVERAGE')

      invocations = 0
      Rake::Task['spec:unit'].clear
      Rake::Task.define_task('spec:unit') { invocations += 1 }

      Rake::Task['coverage:measure'].invoke
      Rake::Task['coverage:measure'].reenable
      Rake::Task['coverage:measure'].invoke

      expect(invocations).to eq(2)
    ensure
      ENV['COVERAGE'] = previous_coverage
    end
  end

  describe 'spec:corpus' do
    it 'clears COVERAGE for spec:corpus_runner and restores the previous value even when it raises' do
      init_repo!
      previous_coverage = ENV.fetch('COVERAGE', nil)
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
    ensure
      ENV['COVERAGE'] = previous_coverage
    end

    it 'reenables spec:corpus_runner so a second invocation in the same process actually reruns it' do
      init_repo!
      previous_coverage = ENV.fetch('COVERAGE', nil)
      ENV.delete('COVERAGE')

      invocations = 0
      Rake::Task['spec:corpus_runner'].clear
      Rake::Task.define_task('spec:corpus_runner') { invocations += 1 }

      Rake::Task['spec:corpus'].invoke
      Rake::Task['spec:corpus'].reenable
      Rake::Task['spec:corpus'].invoke

      expect(invocations).to eq(2)
    ensure
      ENV['COVERAGE'] = previous_coverage
    end
  end

  describe 'coverage:guard' do
    it 'chains measure then changed_lines, in that order' do
      init_repo!
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
