# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'json'
require 'fileutils'
require 'open3'

# TODO.foundation/03-coverage-gate.md item 1: the corpus fixture sweeps
# (examples tagged :corpus -- spec/sirena/parser/{error,info,quadrant}_spec.rb,
# spec/sirena/engine_spec.rb's treemap context, and
# spec/sirena/determinism_spec.rb's "never changes whether a diagram type
# renders at all") assert only that sirena doesn't raise, that its output
# looks SVG-shaped, or (determinism_spec.rb) that two rescued outcome
# strings match -- lines they merely exercise would count as "covered"
# without ever being asserted against if SimpleCov instrumented them. So
# they run in their own rspec process (spec:corpus), which never requires
# simplecov, and spec:unit (via coverage:measure) excludes them with
# --tag ~corpus.
namespace :spec do
  # `spec:corpus` below is the entry point -- this runner exists only so
  # `spec:corpus` can force COVERAGE off first. RSpec::Core::RakeTask spawns
  # its rspec run via `sh`, which inherits ENV, so calling
  # `spec:corpus_runner` directly with COVERAGE=true already set still runs
  # it instrumented: the CLI `--tag corpus` here wins over
  # spec/spec_helper.rb's config-level `filter_run_excluding corpus:` (RSpec
  # applies the CLI tag after spec_helper's config runs, so it does NOT
  # "cancel out" with the exclude). spec/spec_helper.rb's `after(:suite)`
  # hook is the real guard for this path: it raises loudly if any
  # :corpus-tagged example ran while COVERAGE=true, instead of letting
  # corpus-inflated coverage.json ship silently.
  RSpec::Core::RakeTask.new(:corpus_runner) do |task|
    task.rspec_opts = '--tag corpus'
  end

  desc 'Run only the corpus fixture sweep (spec/mermaid/**), isolated from coverage'
  task :corpus do
    previous_coverage_env = ENV.fetch('COVERAGE', nil)
    begin
      ENV.delete('COVERAGE')
      # Same hazard as coverage:measure's spec:unit call below: a Rake task
      # only ever runs once per process, so `rake spec:corpus_runner
      # spec:corpus` on one command line -- reachable since corpus_runner is
      # listed in `rake -T`, see above -- would otherwise leave this invoke
      # a silent no-op (corpus_runner already marked complete from the
      # earlier, direct, top-level invocation), so `spec:corpus` would
      # report success without running the corpus sweep again. Reenable so
      # this call always actually runs it.
      Rake::Task['spec:corpus_runner'].reenable
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

  desc 'Changed-line gate: every lib/ line this branch touches vs COVERAGE_BASE must be 100% covered'
  task :changed_lines do
    base = ENV['COVERAGE_BASE'] || 'origin/main'
    # A ref starting with `-` would be read as another option by `git diff`
    # rather than a revision, in this task's own staleness check below and
    # not just inside simplecov patch (which guards its own call the same
    # way). Reject it here too, before either git invocation runs.
    raise "COVERAGE_BASE #{base.inspect} looks like an option, not a ref" if base.start_with?('-')

    # --find-renames: a pure rename diffs to nothing, not the whole file as
    # new. A changed file outside `.simplecov`'s `cover 'lib/**/*.rb'` glob
    # carries no coverage.json entry, so `simplecov patch` scores it out of
    # scope automatically; a changed file INSIDE lib/ always carries an
    # entry (0% if unloaded), so it can't escape this gate the same way.
    #
    # Do not point --input at coverage/coverage.json directly: --minimum
    # gates line/branch/method uniformly and .simplecov turns branch
    # coverage on, so the raw report would also enforce 100% branch on
    # every changed line. Strip branch/method into a scratch copy first so
    # this task stays line-only.
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
    diff_output, diff_stderr, diff_status =
      Open3.capture3('git', 'diff', '--name-only', '-z', '--merge-base', base)
    unless diff_status.success?
      raise "git diff --name-only --merge-base #{base} failed: #{diff_stderr.strip}"
    end

    untracked_output, untracked_stderr, untracked_status =
      Open3.capture3('git', 'ls-files', '--others', '--exclude-standard', '-z')
    unless untracked_status.success?
      raise "git ls-files --others --exclude-standard failed: #{untracked_stderr.strip}"
    end

    changed_paths = (diff_output.split("\0") + untracked_output.split("\0")).uniq
    report_mtime = File.mtime('coverage/coverage.json')
    stale = changed_paths.select { |path| File.exist?(path) && File.mtime(path) > report_mtime }
    unless stale.empty?
      raise "coverage/coverage.json predates a newer edit to #{stale.join(', ')} -- " \
            'run `rake coverage:measure` again before coverage:changed_lines'
    end

    # A deleted path has no mtime to compare against report_mtime, so the
    # check above silently lets it through. A deleted lib/*.rb file is fine
    # to let through here -- `simplecov patch --find-renames` below handles
    # that deletion itself, and the coverage_rake_spec.rb example "skips a
    # deleted lib/*.rb file..." depends on this task not raising for it. But
    # a deleted SPEC file that was the only thing covering a still-present
    # lib/*.rb line is a different problem: that line's report entry stays
    # at its old (possibly 100%) coverage even though nothing exercises it
    # anymore, and no other guard here catches it (the content-match check
    # below only runs for lib/*.rb paths, and a deleted spec file is never
    # inside lib/). Codex round 17, 2026-09-17: reproduced `simplecov patch`
    # passing at 100% for a lib file whose sole covering spec was deleted in
    # the same diff, using a report generated before that deletion. Fail
    # closed on any deletion outside lib/*.rb, since the report can no
    # longer prove what actually ran against the lib/*.rb files it still
    # claims to cover.
    deleted_non_lib = changed_paths.reject { |path| File.exist?(path) }
      .reject { |path| path.start_with?('lib/') && path.end_with?('.rb') }
    unless deleted_non_lib.empty?
      raise "coverage/coverage.json predates the deletion of #{deleted_non_lib.join(', ')} -- " \
            'run `rake coverage:measure` again before coverage:changed_lines'
    end

    FileUtils.mkdir_p('tmp')
    line_only_report = JSON.parse(File.read('coverage/coverage.json'))
    line_only_report['coverage'].each_value do |file|
      file.delete('branches')
      file.delete('methods')
    end

    # Beats mtime: compares each changed lib/ file's CURRENT content against
    # the report's own `source` line-for-line, not just line count. Skip
    # deleted paths -- `simplecov patch --find-renames` already passes those.
    stale_entry = changed_paths.select do |path|
      next false unless path.start_with?('lib/') && path.end_with?('.rb')
      next false unless File.exist?(path)

      entry = line_only_report['coverage'][path]
      entry.nil? || entry['source'].nil? || entry['source'] != File.readlines(path, chomp: true)
    end
    unless stale_entry.empty?
      raise "coverage/coverage.json has no entry (or a content mismatch against the file's " \
            "current source) for #{stale_entry.join(', ')} -- the report predates this change " \
            'even though its mtime looks newer; run `rake coverage:measure` again before ' \
            'coverage:changed_lines'
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
