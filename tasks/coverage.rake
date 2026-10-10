# frozen_string_literal: true

require "rspec/core/rake_task"
require "json"
require "fileutils"
require "open3"
require "digest"

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
Object.send(:remove_const, :CoverageTasks) if defined?(CoverageTasks)
module CoverageTasks
  MANIFEST_PATH = "tmp/coverage-source-manifest.json"

  module_function

  def without_coverage(&)
    with_coverage_value(nil, &)
  end

  def measure
    with_coverage_value("true") { invoke("spec:unit") }
    write_manifest
  end

  def invoke(name)
    task = Rake::Task[name]
    task.reenable
    task.invoke
  end

  def with_coverage_value(value)
    previous = ENV.fetch("COVERAGE", nil)
    ENV["COVERAGE"] = value
    yield
  ensure
    ENV["COVERAGE"] = previous
  end

  def write_manifest
    tracked, tracked_ok = git_paths("ls-files", "-z")
    untracked, untracked_ok = git_paths(
      "ls-files", "--others", "--exclude-standard", "-z"
    )
    return unless tracked_ok && untracked_ok

    write_manifest_paths((tracked + untracked).uniq)
  end

  def git_paths(*)
    output, _error, status = Open3.capture3("git", *)
    [output.split("\0"), status.success?]
  end

  def write_manifest_paths(paths)
    manifest = paths.each_with_object({}) do |path, hashes|
      next unless File.file?(path) && !File.symlink?(path)

      hashes[path] = Digest::SHA256.file(path).hexdigest
    end
    FileUtils.mkdir_p("tmp")
    File.unlink(MANIFEST_PATH) if File.symlink?(MANIFEST_PATH)
    File.write(MANIFEST_PATH, JSON.generate(manifest))
  end
  REPORT_PATH = "coverage/coverage.json"
  LINE_ONLY_PATH = "tmp/coverage-line-only.json"

  def command
    base = coverage_base
    ensure_report!
    paths = changed_paths(base)
    ensure_report_mtime!(paths)
    ensure_safe_deletions!(paths, base)
    report = line_only_report
    ensure_current_lib_sources!(paths, report)
    ensure_current_non_lib_sources!(paths)
    write_line_only_report(report)
    patch_command(base)
  end

  def coverage_base
    base = ENV["COVERAGE_BASE"] || "origin/main"
    return base unless base.start_with?("-")

    raise "COVERAGE_BASE #{base.inspect} looks like an option, not a ref"
  end

  def ensure_report!
    return if File.exist?(REPORT_PATH)

    raise "#{REPORT_PATH} is missing -- run `rake coverage:measure` " \
          "(or `rake coverage:guard`, which does both) before " \
          "coverage:changed_lines"
  end

  def changed_paths(base)
    changed = git_output!(
      "diff", "--name-only", "-z", "--merge-base", base,
      label: "git diff --name-only --merge-base #{base}"
    )
    untracked = git_output!(
      "ls-files", "--others", "--exclude-standard", "-z",
      label: "git ls-files --others --exclude-standard"
    )
    (changed.split("\0") + untracked.split("\0")).uniq
  end

  def git_output!(*, label:)
    output, error, status = Open3.capture3("git", *)
    raise "#{label} failed: #{error.strip}" unless status.success?

    output
  end

  def ensure_report_mtime!(paths)
    report_mtime = File.mtime(REPORT_PATH)
    stale = paths.select do |path|
      File.exist?(path) && File.mtime(path) > report_mtime
    end
    return if stale.empty?

    raise "#{REPORT_PATH} predates a newer edit to #{stale.join(', ')} -- " \
          "run `rake coverage:measure` again before coverage:changed_lines"
  end

  def ensure_safe_deletions!(paths, base)
    deleted = paths.reject { |path| File.exist?(path) || lib_source?(path) }
    return if deleted.empty?

    raise "#{deleted.join(', ')} deleted vs COVERAGE_BASE=#{base.inspect} -- " \
          "this check has no way to confirm what still covers the lib/*.rb " \
          "files that path exercised, and re-running `rake coverage:measure` " \
          "cannot clear it (it does not change what changed vs " \
          "COVERAGE_BASE). " \
          "Move COVERAGE_BASE past this deletion instead."
  end

  def line_only_report
    if File.symlink?(REPORT_PATH)
      raise "#{REPORT_PATH} is a symlink -- refusing to read through it"
    end

    report = JSON.parse(File.read(REPORT_PATH))
    report["coverage"].each_value do |file|
      file.delete("branches")
      file.delete("methods")
    end
    report
  end

  def ensure_current_lib_sources!(paths, report)
    stale = paths.select do |path|
      next false unless lib_source?(path) && File.exist?(path)

      source = report.dig("coverage", path, "source")
      source.nil? || source != File.readlines(path, chomp: true)
    end
    return if stale.empty?

    raise "#{REPORT_PATH} has no entry (or a content mismatch against the " \
          "file's current source) for #{stale.join(', ')} -- the report " \
          "predates this change even though its mtime looks newer; run " \
          "`rake coverage:measure` again before coverage:changed_lines"
  end

  def ensure_current_non_lib_sources!(paths)
    manifest_path = MANIFEST_PATH
    return unless File.exist?(manifest_path) && !File.symlink?(manifest_path)

    manifest = JSON.parse(File.read(manifest_path))
    stale = paths.select { |path| stale_non_lib?(path, manifest) }
    return if stale.empty?

    raise "#{REPORT_PATH} predates a newer edit to #{stale.join(', ')} " \
          "(content differs from the coverage:measure-time snapshot, even " \
          "though its mtime does not show it) -- run `rake coverage:measure` " \
          "again before coverage:changed_lines"
  end

  def stale_non_lib?(path, manifest)
    return false if lib_source?(path)
    return false unless File.exist?(path) && !File.symlink?(path)

    manifest[path] != Digest::SHA256.file(path).hexdigest
  end

  def lib_source?(path)
    path.start_with?("lib/") && path.end_with?(".rb")
  end

  def write_line_only_report(report)
    FileUtils.mkdir_p("tmp")
    File.unlink(LINE_ONLY_PATH) if File.symlink?(LINE_ONLY_PATH)
    File.write(LINE_ONLY_PATH, JSON.generate(report))
  end

  def patch_command(base)
    ["bundle", "exec", "simplecov", "patch", "--input", LINE_ONLY_PATH,
     "--base", base, "--find-renames", "--minimum", "100"]
  end
end

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
    task.rspec_opts = "--tag corpus"
  end

  desc "Run only the corpus fixture sweep (spec/mermaid/**), " \
       "isolated from coverage"
  task :corpus do
    CoverageTasks.without_coverage do
      CoverageTasks.invoke("spec:corpus_runner")
    end
  end

  desc "Run every spec except the corpus fixture sweep"
  RSpec::Core::RakeTask.new(:unit) do |task|
    task.rspec_opts = "--tag ~corpus"
  end
end

namespace :coverage do
  desc "Run spec:unit under SimpleCov (.simplecov enforces the line floor)"
  task :measure do
    CoverageTasks.measure
  end

  desc "Changed-line gate: every lib/ line this branch touches vs " \
       "COVERAGE_BASE must be 100% covered"
  task :changed_lines do
    sh(*CoverageTasks.command)
  end

  desc "coverage:measure, then the changed-line gate"
  task guard: %i[measure changed_lines]
end
