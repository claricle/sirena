# frozen_string_literal: true

require "fileutils"
require "json"
require "yaml"
require_relative "seeded_scoreboard_repo"
require_relative "repository_paths"

# Local event simulations use synthetic verdicts, not oracle evidence.
# Both gate commands run unchanged production code against committed fixtures.
class SeededFreshnessRepo < SeededScoreboardRepo
  MODES = %w[
    pull_request fork_pull_request push merge_group workflow_dispatch
    workflow_dispatch_consistency schedule
  ].freeze
  TARGET = "pie/target.mmd"
  SOURCE = "pie\n\"Apples\": 3\n"
  BROKEN = "pie\nnot a pie entry\n"

  Command = Struct.new(:out, :err, :status, keyword_init: true) do
    def json
      JSON.parse(out)
    end
  end

  Checks = Struct.new(:baseline, :freshness, keyword_init: true) do
    def statuses
      [baseline.status.exitstatus, freshness.status.exitstatus]
    end

    def failure
      return freshness.out if baseline.status.success?

      baseline.json.fetch("errors").join("\n")
    end
  end

  def initialize(root, mode:, scenario:)
    super(root)
    @mode = mode
    install_task
    write_sources(scenario)
    record_corpus
    @base = commit
    git("update-ref", "refs/remotes/origin/main", base)
    seed_head(scenario)
    commit
  end

  def ledgers
    { "corpus" => [], "conformance" => [], "layout-parity" => [] }
  end

  def commit
    git("add", ".")
    git("commit", "--quiet", "--allow-empty", "-m", "record fixtures")
    git("rev-parse", "HEAD")
  end

  def consistency_only?
    %w[workflow_dispatch_consistency schedule].include?(@mode)
  end

  def expected_baseline
    consistency_only? ? nil : base
  end

  def baseline_mode
    return "workflow_dispatch" if @mode == "workflow_dispatch_consistency"

    @mode
  end

  def checks
    out, err, status = run_cli(event_name, payload)
    Checks.new(baseline: Command.new(out: out, err: err, status: status),
               freshness: corpus_command("corpus:check"))
  end

  private

  def install_task
    %w[tasks/corpus.rake lib/sirena/corpus_type_names.rb].each do |path|
      destination = File.join(dir, path)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(SpecSupport::RepositoryPaths.path(path), destination)
    end
  end

  def write_sources(scenario)
    FileUtils.mkdir_p(File.join(dir, "spec/mermaid/pie"))
    File.write(File.join(dir, "spec/mermaid/pie/anchor.mmd"), SOURCE)
    broken = %i[stale_improvement recorded_improvement].include?(scenario)
    write_target(broken ? BROKEN : SOURCE)
    verdicts = %w[pie/anchor.mmd pie/target.mmd].map do |id|
      { "case" => id, "verdict" => "valid" }
    end
    File.write(File.join(dir, "spec/mermaid/corpus-verdicts.yml"),
               YAML.dump(verdicts))
  end

  def write_target(source)
    File.write(File.join(dir, "spec/mermaid", TARGET), source)
  end

  def seed_head(scenario)
    case scenario
    when :regression
      write_target(BROKEN)
    when :deletion
      File.delete(File.join(dir, "spec/mermaid", TARGET))
    when :stale_improvement, :recorded_improvement then write_target(SOURCE)
    end
    record_corpus if record_head?(scenario)
  end

  def record_head?(scenario)
    scenario == :recorded_improvement ||
      (%i[regression deletion].include?(scenario) && !consistency_only?)
  end

  def event_name
    return "pull_request" if @mode == "fork_pull_request"

    baseline_mode
  end

  def payload
    return {} if consistency_only?

    event(event_name, fork: @mode == "fork_pull_request")
  end

  def record_corpus
    paths = Dir[File.join(dir, "spec/mermaid/*/*.mmd")]
    rows = paths.map { |path| measured_row(path) }
    File.write(File.join(dir, "scoreboard/corpus.json"), JSON.generate(rows))
  end

  def measured_row(path)
    row = { "case" => path.delete_prefix("#{dir}/spec/mermaid/"),
            "verdict" => "valid", "pass" => true }
    Sirena::Engine.new.render(File.read(path))
    row
  rescue Sirena::Parser::ParseError => e
    row.merge("pass" => false, "stage" => "parse",
              "exception_class" => e.class.name)
  end

  def corpus_command(task)
    args = [RbConfig.ruby, "-I", SpecSupport::RepositoryPaths.path("lib"),
            Gem.bin_path("rake", "rake"), "-f", "tasks/corpus.rake", task]
    out, err, status = Open3.capture3(*args, chdir: dir)
    Command.new(out: out, err: err, status: status)
  end
end
