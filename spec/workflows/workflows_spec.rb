# frozen_string_literal: true

require "yaml"
require "tmpdir"
require "open3"
require "rbconfig"
require_relative "../../scripts/check_workflow_pins"
require_relative "../../scripts/lane_verdict"

# Builders for the workflow-shaped hashes the CI workflow specs feed to scripts/.
module WorkflowHelpers
  # `|| true` or `|| :` as a whole shell word, whatever follows it.
  # A redirection operator (`>`, `<`) also ends the word.
  IGNORED_STATUS = /\|\|\s*(?:true|:)(?=[\s;&|)<>]|\z)/

  def workflow_with(uses)
    { "jobs" => { "j" => { "timeout-minutes" => 1, "steps" => [{ "uses" => uses }] } } }
  end

  def run_commands(job)
    job.fetch("steps").filter_map { |step| step["run"] }
  end

  # Ways a job can fail without blocking its lane: failure tolerated, a
  # skipped step, or a command whose status is thrown away.
  def swallowed_failures(name, job)
    steps = job.fetch("steps")
    tolerated = [job, *steps].select { |h| h.key?("continue-on-error") }
    skipped = steps.select { |step| step.key?("if") }
    ignored = run_commands(job).grep(IGNORED_STATUS)
    [*tolerated, *skipped, *ignored].map { |found| "#{name}: #{found.inspect}" }
  end

  def unsound_aggregator?(name, job)
    job["if"] != "${{ always() }}" ||
      run_commands(job) != ["ruby scripts/lane_verdict.rb"] ||
      swallowed_failures(name, job).any?
  end

  def result(name, outcome)
    { name => { "result" => outcome, "outputs" => {} } }
  end
end

# The subject is a set of YAML files, not a class.
RSpec.describe "CI workflows" do # rubocop:disable RSpec/DescribeClass
  let(:root) { File.expand_path("../..", __dir__) }
  let(:ci) { YAML.safe_load_file(File.join(root, ".github/workflows/ci.yml")) }
  let(:aggregators) { %w[fast-lane full-lane] }

  let(:workflow_files) { Dir[File.join(root, ".github/workflows/*.yml")] }

  include WorkflowHelpers

  describe WorkflowPins do
    it "finds no unpinned external reference and no missing timeout in the tracked workflows" do
      expect(workflow_files).not_to be_empty
      expect(workflow_files.flat_map { |f| described_class.problems(f) }).to eq([])
    end

    {
      "actions/checkout@v4" => true,
      "actions/checkout@main" => true,
      "actions/checkout@11d5960a" => true,
      "actions/checkout@11d5960a326750d5838078e36cf38b85af67726" => true,
      "actions/checkout@11d5960a326750d5838078e36cf38b85af677262" => false,
      "actions/checkout@11D5960A326750D5838078E36CF38B85AF677262" => true,
      "./.github/workflows/links.yml" => false,
      "metanorma/ci/.github/workflows/x.yml@main" => true,
    }.each do |ref, rejected|
      it "#{rejected ? 'rejects' : 'accepts'} #{ref}" do
        expect(described_class.unpinned(workflow_with(ref))).to eq(rejected ? [ref] : [])
      end
    end

    it "sees a job-level reusable workflow reference too" do
      wf = { "jobs" => { "j" => { "uses" => "o/r/.github/workflows/w.yml@main" } } }
      expect(described_class.unpinned(wf)).to eq(["o/r/.github/workflows/w.yml@main"])
    end

    it "flags a job with no timeout-minutes but not a reusable-workflow call" do
      wf = { "jobs" => { "a" => { "steps" => [] }, "b" => { "uses" => "./w.yml" },
                         "c" => { "timeout-minutes" => 3 } } }
      expect(described_class.without_timeout(wf)).to eq(["a"])
    end

    it "exits non-zero from the script when a seeded workflow is unpinned" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "scripts"))
        FileUtils.mkdir_p(File.join(dir, ".github/workflows"))
        FileUtils.cp(File.join(root, "scripts/check_workflow_pins.rb"), File.join(dir, "scripts"))
        File.write(File.join(dir, ".github/workflows/x.yml"),
                   "on: push\njobs:\n  j:\n    timeout-minutes: 1\n    steps:\n      - uses: actions/checkout@v4\n")
        _, err, status = Open3.capture3(RbConfig.ruby, File.join(dir, "scripts/check_workflow_pins.rb"))
        expect(status.exitstatus).to eq(1)
        expect(err).to include("unpinned actions/checkout@v4")
      end
    end
  end

  describe "swallowed failures in a run command" do
    {
      "check || true" => true,
      "check ||true" => true,
      "check || :" => true,
      "check || true; echo done" => true,
      "check || true # temporary workaround" => true,
      "check || true && echo done" => true,
      "check || true | tee log" => true,
      "check || true|tee log" => true,
      "check || true&&echo done" => true,
      "check || : ; echo done" => true,
      "(check || true)" => true,
      "{ check || true; }" => true,
      "check || true\necho done" => true,
      "check || true>/dev/null" => true,
      "check || true>>log" => true,
      "check || true>&2" => true,
      "check || true 2>/dev/null" => true,
      "check || :>/dev/null" => true,
      "check || true</dev/null" => true,
      "check || true<<<input" => true,
      "check || true<>log" => true,
      "check || truest" => false,
      "check || true_exit" => false,
      "check || true#note" => false,
      "check || :foo" => false,
      "check || true2>/dev/null" => false,
      "check || truex>/dev/null" => false,
      "check || truex</dev/null" => false,
      "check && true" => false,
      "check | grep true" => false,
    }.each do |command, swallows|
      it "#{swallows ? 'flags' : 'passes'} #{command.inspect}" do
        job = { "steps" => [{ "run" => command }] }
        expect(swallowed_failures("j", job).any?).to eq(swallows)
      end
    end
  end

  describe LaneVerdict do
    it "is green only when every child succeeded" do
      needs = result("a", "success").merge(result("b", "success"))
      expect(described_class.failures(needs)).to eq([])
    end

    %w[failure skipped cancelled].each do |outcome|
      it "is red when one child is #{outcome}, the others succeeded" do
        needs = result("a", "success").merge(result("b", outcome))
        expect(described_class.failures(needs)).to eq(["b: #{outcome.inspect}"])
      end
    end

    it "is red when there is nothing to judge" do
      expect(described_class.failures({})).not_to be_empty
    end
  end

  describe "ci.yml topology" do
    let(:jobs) { ci.fetch("jobs") }

    it "runs on pull requests, merge queue, push, dispatch and a nightly schedule" do
      triggers = ci["on"] || ci[true]
      expect(triggers.keys).to include("pull_request", "merge_group", "push", "workflow_dispatch", "schedule")
    end

    it "names both aggregators with stable job names, always() and a timeout" do
      aggregators.each do |name|
        job = jobs.fetch(name)
        expect(job["name"]).to eq(name)
        expect(job["if"]).to include("always()")
        expect(job["timeout-minutes"]).to be_a(Integer)
      end
    end

    it "hangs every other gate job off an aggregator, so none runs loose" do
      needed = aggregators.flat_map { |a| Array(jobs.fetch(a)["needs"]) }
      gates = jobs.keys - aggregators - ["cascade"]
      expect(gates - needed).to eq([])
    end

    it "keeps the docs jobs out of the fast lane" do
      expect(jobs["fast-lane"]["needs"]).not_to include("docs-build", "links")
    end

    it "gates the release cascade on the fast lane only, so a links outage cannot suppress it" do
      expect(Array(jobs.fetch("cascade")["needs"])).to eq(["fast-lane"])
      expect(jobs.fetch("fast-lane")["needs"]).to include("unit")
    end

    it "feeds each aggregator the whole needs context" do
      aggregators.each do |name|
        env = jobs.fetch(name)["steps"].filter_map { |s| s["env"] }.reduce({}, :merge)
        expect(env["NEEDS_JSON"]).to eq("${{ toJSON(needs) }}")
      end
    end

    %w[corpus conformance fresh-resolution].each do |slot|
      it "hangs the #{slot} job off the full lane" do
        expect(jobs.fetch("full-lane")["needs"]).to include(slot)
      end

      it "keeps the #{slot} job out of the fast lane" do
        expect(jobs.fetch("fast-lane")["needs"]).not_to include(slot)
      end
    end

    {
      "corpus" => ["bundle exec rake corpus:check"],
      "conformance" => ["bundle exec rake conformance:check",
                        "bundle exec rspec spec/svg_conformance_spec.rb"],
    }.each do |slot, commands|
      it "runs #{commands.join(' and ')} in the #{slot} job" do
        expect(run_commands(jobs.fetch(slot))).to include(*commands)
      end
    end

    it "keeps every slot gate live: no job condition, no swallowed failure" do
      gates = %w[lint corpus conformance fresh-resolution]
      conditional = gates.select { |name| jobs.fetch(name).key?("if") }
      leaks = gates.flat_map { |n| swallowed_failures(n, jobs.fetch(n)) }
      expect(conditional + leaks).to eq([])
    end

    it "judges each lane with the verdict script, always" do
      unsound = aggregators.select { |n| unsound_aggregator?(n, jobs.fetch(n)) }
      expect(unsound).to eq([])
    end

    it "runs rubocop as the lint job, hung off fast-lane" do
      lint = jobs.fetch("lint")
      expect(lint["steps"].filter_map { |s| s["run"] }).to include("bundle exec rubocop")
      expect(jobs.fetch("fast-lane")["needs"]).to include("lint")
    end

    it "has no standalone lint workflow file any more" do
      expect(workflow_files.map { |f| File.basename(f) }).not_to include("lint.yml")
    end

    describe "fresh-resolution job" do
      it "does not restore a cached bundle, so gems resolve from scratch" do
        steps = jobs.fetch("fresh-resolution")["steps"]
        setup = steps.find { |s| s["uses"].to_s.include?("setup-ruby") }
        expect(setup.fetch("with", {})["bundler-cache"]).to be_falsey
      end

      it "deletes any lockfile before it installs" do
        script = run_commands(jobs.fetch("fresh-resolution")).join("\n")
        expect(script).to match(/rm -f Gemfile\.lock.*bundle install/m)
      end

      it "requires sirena and svg_conform in the same bundle" do
        smoke = 'require "sirena"; require "svg_conform"'
        runs = run_commands(jobs.fetch("fresh-resolution"))
        expect(runs).to include("bundle exec ruby -e '#{smoke}'")
      end

      it "finishes with the whole suite" do
        runs = run_commands(jobs.fetch("fresh-resolution"))
        expect(runs.last).to eq("bundle exec rspec")
      end
    end
  end
end
