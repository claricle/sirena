# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'json'
require 'fileutils'
require 'open3'

# TODO.foundation/03-coverage-gate.md item 1: the corpus fixture sweeps
# (examples tagged :corpus -- spec/sirena/parser/{error,info,quadrant}_spec.rb
# and spec/sirena/engine_spec.rb's treemap context) assert only that sirena
# doesn't raise, or that its output looks SVG-shaped. Running them in the same
# process SimpleCov instruments would let lines they merely exercise, and
# never assert against, count as "covered" -- exactly the inflation item 1
# requires the coverage number be provably free of. So they get their own
# rspec process (spec:corpus), which never requires simplecov at all, and
# the coverage-measuring process (spec:unit, via coverage:measure) excludes
# them with --tag ~corpus. Verified once by comparing the two: with the
# corpus examples included, line coverage read higher than spec:unit alone
# reports -- recorded in the gate record for this branch, not re-checked on
# every run (that would just re-run the suite twice for no gate purpose).
namespace :spec do
  # Undocumented on purpose: `spec:corpus` below is the entry point. This
  # runner exists only so `spec:corpus` can force COVERAGE off around it --
  # RSpec::Core::RakeTask spawns its rspec run via `sh`, which always
  # inherits the parent process's ENV, so the corpus sweep would otherwise
  # be instrumented whenever COVERAGE=true reaches this task from anywhere
  # (the invoking shell, CI, or an earlier coverage:measure chained on the
  # same command line) rather than only when this file itself set it.
  RSpec::Core::RakeTask.new(:corpus_runner) do |task|
    task.rspec_opts = '--tag corpus'
  end

  desc 'Run only the corpus fixture sweep (spec/mermaid/**), isolated from coverage'
  task :corpus do
    previous_coverage_env = ENV.fetch('COVERAGE', nil)
    begin
      ENV.delete('COVERAGE')
      Rake::Task['spec:corpus_runner'].invoke
    ensure
      ENV['COVERAGE'] = previous_coverage_env
    end
  end

  desc 'Run every spec except the corpus fixture sweep'
  RSpec::Core::RakeTask.new(:unit) do |task|
    task.rspec_opts = '--tag ~corpus'
  end
end

namespace :coverage do
  desc 'Run spec:unit under SimpleCov (.simplecov enforces the line floor)'
  task :measure do
    # Restore rather than leave set: ENV survives past this task in the same
    # process, so `rake coverage:measure spec:corpus` on one command line
    # would otherwise leave COVERAGE=true for spec:corpus's own subprocess
    # too, and spec_helper.rb requires simplecov for ANY process that sees
    # it -- defeating the corpus-exclusion this task depends on.
    previous_coverage_env = ENV.fetch('COVERAGE', nil)
    begin
      ENV['COVERAGE'] = 'true'
      # A Rake task only ever runs once per process -- `invoke` is a no-op
      # on a task already marked complete. `rake spec:unit coverage:measure`
      # on one command line would otherwise skip the instrumented run
      # entirely (spec:unit already ran, uninstrumented, as its own
      # top-level task) and this task would silently do nothing.
      Rake::Task['spec:unit'].reenable
      Rake::Task['spec:unit'].invoke
    ensure
      ENV['COVERAGE'] = previous_coverage_env
    end
  end

  desc 'Changed-line gate: every lib/ line this branch touches vs --base must be 100% covered'
  task :changed_lines do
    base = ENV['COVERAGE_BASE'] || 'origin/main'
    # A ref starting with `-` would be read as another option by `git diff`
    # rather than a revision, in this task's own staleness check below and
    # not just inside simplecov patch (which guards its own call the same
    # way). Reject it here too, before either git invocation runs.
    raise "COVERAGE_BASE #{base.inspect} looks like an option, not a ref" if base.start_with?('-')

    # --find-renames: a pure rename (no content change) then diffs to
    # nothing instead of counting the whole moved file as new/uncovered.
    # A changed file outside `.simplecov`'s `cover 'lib/**/*.rb'` glob
    # (specs, rake tasks, docs, this file) carries no coverage.json entry,
    # so `simplecov patch` scores it out of scope automatically -- that IS
    # the file-scope rule. A changed file INSIDE lib/ always carries an
    # entry, 0% if the suite never loads it, so it cannot escape this gate
    # the same way.
    #
    # Do not point --input at coverage/coverage.json directly: simplecov
    # patch's --minimum gates every criterion present in the input file
    # (line, branch, method) uniformly, with no per-criterion flag, and
    # .simplecov turns branch coverage on. Feeding it the raw report would
    # silently also enforce 100% branch on every changed line. Strip
    # branch/method from a scratch copy first so this task stays line-only;
    # the real report (coverage/coverage.json) still carries branch data
    # untouched for anyone reading it directly.
    unless File.exist?('coverage/coverage.json')
      raise 'coverage/coverage.json is missing -- run `rake coverage:measure` ' \
            '(or `rake coverage:guard`, which does both) before coverage:changed_lines'
    end

    # A report generated before this diff's own edits would silently pass
    # them (simplecov patch has no lines to compare a fresher change
    # against). Run coverage:measure again if any of these are listed.
    # `git diff --name-only` alone misses a brand-new file that was never
    # `git add`ed -- add `ls-files --others --exclude-standard` (untracked,
    # unignored) the same way simplecov patch's own ChangedLines does, or a
    # just-created uncovered file passes silently. `-z` on both: git quotes
    # a non-ASCII path in newline-delimited output (e.g. "caf\303\251.rb"),
    # and that quoted string never matches a real path on disk, so the
    # unquoted, NUL-delimited form is the only one safe to split and stat.
    diff_output, diff_status = Open3.capture2('git', 'diff', '--name-only', '-z', '--merge-base', base)
    raise "git diff --name-only --merge-base #{base} failed" unless diff_status.success?

    untracked_output, untracked_status = Open3.capture2('git', 'ls-files', '--others', '--exclude-standard', '-z')
    raise 'git ls-files --others --exclude-standard failed' unless untracked_status.success?

    changed_paths = (diff_output.split("\0") + untracked_output.split("\0")).uniq
    report_mtime = File.mtime('coverage/coverage.json')
    stale = changed_paths.select { |path| File.exist?(path) && File.mtime(path) > report_mtime }
    unless stale.empty?
      raise "coverage/coverage.json predates a newer edit to #{stale.join(', ')} -- " \
            'run `rake coverage:measure` again before coverage:changed_lines'
    end

    FileUtils.mkdir_p('tmp')
    line_only_report = JSON.parse(File.read('coverage/coverage.json'))
    line_only_report['coverage'].each_value do |file|
      file.delete('branches')
      file.delete('methods')
    end
    File.write('tmp/coverage-line-only.json', JSON.generate(line_only_report))

    # Multi-arg form: bypasses the shell entirely, so a hostile COVERAGE_BASE
    # (e.g. containing `;` or backticks) cannot execute a second command --
    # the single-string form would have passed it to `sh -c` unescaped.
    sh 'bundle', 'exec', 'simplecov', 'patch', '--input', 'tmp/coverage-line-only.json',
       '--base', base, '--find-renames', '--minimum', '100'
  end

  desc 'coverage:measure, then the changed-line gate'
  task guard: [:measure, :changed_lines]
end
