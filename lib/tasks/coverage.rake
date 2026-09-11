# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'json'
require 'fileutils'

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
  desc 'Run only the corpus fixture sweep (spec/mermaid/**), isolated from coverage'
  RSpec::Core::RakeTask.new(:corpus) do |task|
    task.rspec_opts = '--tag corpus'
  end

  desc 'Run every spec except the corpus fixture sweep'
  RSpec::Core::RakeTask.new(:unit) do |task|
    task.rspec_opts = '--tag ~corpus'
  end
end

namespace :coverage do
  desc 'Run spec:unit under SimpleCov (.simplecov enforces the line floor)'
  task :measure do
    ENV['COVERAGE'] = 'true'
    Rake::Task['spec:unit'].invoke
  end

  desc 'Changed-line gate: every lib/ line this branch touches vs --base must be 100% covered'
  task :changed_lines do
    base = ENV['COVERAGE_BASE'] || 'origin/main'
    # --find-renames: a pure rename (no content change) then diffs to
    # nothing instead of counting the whole moved file as new/uncovered.
    # A changed file SimpleCov never tracked (specs, rake tasks, docs,
    # this file) carries no coverage.json entry, so `simplecov patch`
    # scores it out of scope automatically -- that IS the file-scope rule:
    # only files the coverage report already carries are gated.
    #
    # simplecov patch's --minimum gates every MEASURED criterion (line,
    # branch, method) uniformly, with no per-criterion flag. .simplecov
    # enables branch coverage for the report, so branch data is present in
    # coverage.json and gating straight off it would silently enforce 100%
    # branch on every changed line today -- ahead of this item's own staged
    # branch timeline. So the gate reads a scratch copy of the report with
    # branch/method data stripped, keeping this task line-only; branch stays
    # measured and visible in the real report untouched.
    unless File.exist?('coverage/coverage.json')
      abort "coverage/coverage.json is missing -- run `rake coverage:measure` " \
            '(or `rake coverage:guard`, which does both) before coverage:changed_lines'
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
