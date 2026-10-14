# frozen_string_literal: true

require "json"
require_relative "seeded_ci_repo"

# Disposable committed ledgers with a fetched main ref, like actions/checkout.
class SeededScoreboardRepo
  attr_reader :dir, :base

  def initialize(root)
    @dir = File.join(root, "repo")
    Dir.mkdir(dir)
    git("init", "--quiet", "--initial-branch=main")
    Dir.mkdir(File.join(dir, "scoreboard"))
    write(ledgers)
    @base = commit
    git("update-ref", "refs/remotes/origin/main", base)
    git("checkout", "--quiet", "-b", "feature")
  end

  def ledgers
    { "corpus" => [{ "case" => "flowchart/a.mmd",
                     "verdict" => "valid", "pass" => true }],
      "conformance" => [{ "case" => "flowchart/a.mmd",
                          "status" => "conformant" }],
      "layout-parity" => [{ "case" => "flowchart/a.mmd", "summary" => {
        "hard_failure" => false, "metrics" => {
          "worst_e_c" => 0.02, "worst_e_w" => 0.03, "worst_e_h" => 0.04,
          "worst_e_a" => 0.05, "worst_analog" => nil
        }
      } }] }
  end

  def write(data)
    data.each do |name, rows|
      File.write(File.join(dir, "scoreboard", "#{name}.json"),
                 JSON.generate(rows))
    end
  end

  def commit
    git("add", "scoreboard")
    git("commit", "--quiet", "--allow-empty", "-m", "record scoreboard")
    git("rev-parse", "HEAD")
  end

  def git(*)
    out, err, status = Open3.capture3("git", *SeededCiRepo::IDENTITY, *,
                                      chdir: dir)
    raise "git failed: #{err}" unless status.success?

    out.strip
  end

  def event(name, fork: false)
    case name
    when "pull_request"
      { "pull_request" => {
        "base" => { "ref" => "main", "repo" => { "full_name" => "o/r" } },
        "head" => { "repo" => { "full_name" => fork ? "fork/r" : "o/r" } },
      } }
    when "push" then { "before" => base }
    when "merge_group" then { "merge_group" => { "base_sha" => base } }
    when "workflow_dispatch" then { "inputs" => { "baseline_sha" => base } }
    end
  end

  def record_and_run(data, event_name, payload)
    write(data)
    commit
    run_cli(event_name, payload)
  end

  def recorded_improvement(event_name)
    data = ledgers
    metrics(data)["worst_e_c"] = 0.01
    data.each_value do |rows|
      rows << rows.first.merge("case" => "flowchart/new.mmd")
    end
    record_and_run(data, event_name, event(event_name))
  end

  def malformed_baseline
    write("corpus" => {})
    baseline = commit
    record_and_run(ledgers, "push", { "before" => baseline })
  end

  def metrics(data)
    data.fetch("layout-parity").first.fetch("summary").fetch("metrics")
  end

  def metric_increase(metric)
    data = ledgers
    metrics(data)[metric] = 0.1
    write(data)
    baseline = commit
    metrics(data)[metric] = 0.2
    record_and_run(data, "push", { "before" => baseline })
  end

  def run_cli(event_name, payload)
    event_path = File.join(File.dirname(dir), "event.json")
    File.write(event_path, JSON.generate(payload))
    script = File.expand_path("../../scripts/scoreboard_baseline.rb", __dir__)
    Open3.capture3({ "GITHUB_EVENT_NAME" => event_name,
                     "GITHUB_EVENT_PATH" => event_path },
                   RbConfig.ruby, script, chdir: dir)
  end
end
