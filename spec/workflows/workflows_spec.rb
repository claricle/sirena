# frozen_string_literal: true

require "yaml"
require "tmpdir"
require "open3"
require "rbconfig"
require_relative "../../scripts/check_workflow_pins"
require_relative "../../scripts/lane_verdict"

# Builders for the workflow-shaped hashes the CI workflow specs feed to
# scripts/.
module WorkflowHelpers
  def workflow_with(uses)
    { "jobs" => { "j" => { "timeout-minutes" => 1,
                           "steps" => [{ "uses" => uses }] } } }
  end

  def reusable_workflow(uses)
    { "jobs" => { "j" => { "uses" => uses } } }
  end

  def workflow_without_timeout
    jobs = {
      "a" => { "steps" => [] },
      "b" => { "uses" => "./w.yml" },
      "c" => { "timeout-minutes" => 3 },
    }
    { "jobs" => jobs }
  end

  def result(name, outcome)
    { name => { "result" => outcome, "outputs" => {} } }
  end

  def cascade_values(steps)
    [steps.map { |step| step["name"] },
     steps.map { |step| step["run"] }.join.include?("do-release")]
  end

  def changelog_step(jobs)
    jobs.fetch("preflight").fetch("steps").find do |candidate|
      candidate["run"]&.include?("scripts/check_changelog.rb")
    end
  end

  def changelog_values(step)
    [step["run"], step.dig("env", "NEXT_VERSION")]
  end

  def named_step(job, name)
    job.fetch("steps").find { |step| step["name"] == name }
  end

  def release_requirement_values(jobs)
    release_job = jobs.fetch("release")
    [Array(release_job["needs"]), release_job["uses"]]
  end

  def checked_main_values(jobs)
    command = named_step(
      jobs.fetch("release"),
      "require the checked main head",
    ).fetch("run")
    fragments = [
      "commits/main",
      "check-runs?per_page=100",
      "check_release_source.rb checked-main",
    ]
    fragments.map { |fragment| command.include?(fragment) }
  end

  def version_push_values(jobs)
    release_job = jobs.fetch("release")
    prepare = named_step(
      release_job,
      "prepare version-only release commit",
    ).fetch("run")
    push = named_step(release_job, "push version commit and tag").fetch("run")
    checks = [
      "check_release_source.rb write-version",
      "check_release_source.rb version-only",
    ]
    [checks.all? { |fragment| prepare.include?(fragment) },
     push.include?("git push --atomic")]
  end

  def published_gem_values(jobs)
    release_job = jobs.fetch("release")
    build = named_step(release_job, "build gem").fetch("run")
    publish = named_step(release_job, "publish gem")
    [
      build,
      publish.fetch("run").include?(
        'gem push "$RUNNER_TEMP/sirena-$TARGET_VERSION.gem"',
      ),
      publish.dig("env", "RUBYGEMS_API_KEY"),
    ]
  end

  def expected_published_gem_values
    command =
      "gem build sirena.gemspec --output " \
      '"$RUNNER_TEMP/sirena-$TARGET_VERSION.gem"'
    [command, true, "${{ secrets.CLARICLE_CI_RUBYGEMS_API_KEY }}"]
  end

  def oracle_browser_scope(jobs)
    steps = jobs.fetch("oracle-toolchain").fetch("steps")
    %w[canary check].map do |command|
      step = steps.find do |candidate|
        candidate["run"] == "npm run oracle:#{command}"
      end
      step.fetch("env", nil)
    end
  end

  def expected_unit_matrix
    shards = %w[1/3 2/3 3/3]
    {
      "os" => %w[ubuntu-latest macos-latest windows-latest],
      "ruby" => %w[3.2 3.3 3.4],
      "experimental" => [false],
      "shard" => shards,
      "exclude" => %w[ubuntu-latest macos-latest].product(shards.drop(1))
        .map { |os, shard| { "os" => os, "shard" => shard } },
      "include" => expected_ruby4_cells(shards),
    }
  end

  # Ruby 4.0 is experimental everywhere; only Windows is split into shards.
  def expected_ruby4_cells(shards)
    cell = { "ruby" => "4.0", "experimental" => true }
    unsharded = %w[ubuntu-latest macos-latest].map do |os|
      { "os" => os }.merge(cell)
    end
    unsharded + shards.map do |shard|
      { "os" => "windows-latest", "shard" => shard }.merge(cell)
    end
  end

  def unit_rake_step(jobs)
    jobs.fetch("unit").fetch("steps").find do |step|
      step["run"] == "bundle exec rake"
    end
  end

  def leptris_selector
    "${{ matrix.os == 'windows-latest' && " \
      "matrix.ruby == '3.2' && '1' || '' }}"
  end
end

# The subject is a set of YAML files, not a class.
RSpec.describe "CI workflows" do # rubocop:disable RSpec/DescribeClass
  let(:root) { File.expand_path("../..", __dir__) }
  let(:ci) { YAML.safe_load_file(File.join(root, ".github/workflows/ci.yml")) }
  let(:release) do
    YAML.safe_load_file(File.join(root, ".github/workflows/release.yml"))
  end
  let(:aggregators) { %w[fast-lane full-lane] }

  let(:workflow_files) { Dir[File.join(root, ".github/workflows/*.yml")] }

  include WorkflowHelpers

  describe WorkflowPins do
    it "finds no unpinned external reference and no missing timeout in the " \
       "tracked workflows" do
      expect(workflow_files).not_to be_empty
      problems = workflow_files.flat_map { |f| described_class.problems(f) }
      expect(problems).to eq([])
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
        expect(described_class.unpinned(workflow_with(ref)))
          .to eq(rejected ? [ref] : [])
      end
    end

    it "sees a job-level reusable workflow reference too" do
      ref = "o/r/.github/workflows/w.yml@main"
      expect(described_class.unpinned(reusable_workflow(ref))).to eq([ref])
    end

    it "flags a job with no timeout-minutes but not a reusable-workflow call" do
      expect(described_class.without_timeout(workflow_without_timeout))
        .to eq(["a"])
    end

    it "exits non-zero from the script when a seeded workflow is unpinned" do
      Dir.mktmpdir do |dir|
        scripts = File.join(dir, "scripts")
        workflows = File.join(dir, ".github/workflows")
        FileUtils.mkdir_p([scripts, workflows])
        script = File.join(scripts, "check_workflow_pins.rb")
        FileUtils.cp(File.join(root, "scripts/check_workflow_pins.rb"), script)
        workflow = "on: push\njobs:\n  j:\n    timeout-minutes: 1\n    " \
                   "steps:\n      - uses: actions/checkout@v4\n"
        File.write(File.join(workflows, "x.yml"), workflow)
        _, err, status = Open3.capture3(RbConfig.ruby, script)
        expect(status.exitstatus).to eq(1)
        expect(err).to include("unpinned actions/checkout@v4")
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
    def jobs
      ci.fetch("jobs")
    end

    it "runs every stable Ruby on every OS and keeps Ruby 4 experimental" do
      expect(jobs.fetch("unit").dig("strategy", "matrix"))
        .to eq(expected_unit_matrix)
    end

    it "selects leptris FFI only for Ruby 3.2 on Windows" do
      expect(unit_rake_step(jobs).dig("env", "LEPTRIS_NO_NATIVE"))
        .to eq(leptris_selector)
    end

    it "gives the rake step a shard only on Windows" do
      expect(unit_rake_step(jobs).dig("env", "SIRENA_SPEC_SHARD"))
        .to eq("${{ matrix.os == 'windows-latest' && matrix.shard || '' }}")
    end

    it "runs on pull requests, merge queue, push, dispatch and a nightly " \
       "schedule" do
      triggers = ci["on"] || ci[true]
      expect(triggers.keys).to include("pull_request", "merge_group", "push",
                                       "workflow_dispatch", "schedule")
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

    it "gates the release cascade on the fast lane only, so a links outage " \
       "cannot suppress it" do
      expect(Array(jobs.fetch("cascade")["needs"])).to eq(["fast-lane"])
      expect(jobs.fetch("fast-lane")["needs"]).to include("unit")
    end

    it "feeds each aggregator the whole needs context" do
      aggregators.each do |name|
        steps = jobs.fetch(name)["steps"]
        env = steps.filter_map { |s| s["env"] }.reduce({}, :merge)
        expect(env["NEEDS_JSON"]).to eq("${{ toJSON(needs) }}")
      end
    end

    it "wires lint into the fast lane, with parity and a standalone corpus " \
       "job still unfilled" do
      expect(jobs.keys).to include("lint")
      expect(jobs.keys).not_to include("corpus", "parity")
    end

    it "gates the full lane on conformance and fresh-resolution" do
      needs = jobs.fetch("full-lane")["needs"]
      expect(needs).to include("conformance", "fresh-resolution")
    end

    it "gives fresh-resolution no bundler cache" do
      steps = jobs.fetch("fresh-resolution")["steps"]
      expect(steps.filter_map { |s| s.dig("with", "bundler-cache") })
        .to be_empty
    end

    it "installs fresh in fresh-resolution, then runs the suite" do
      steps = jobs.fetch("fresh-resolution")["steps"]
      expect(steps.filter_map { |s| s["run"] })
        .to eq(["bundle install", "bundle exec rake"])
    end

    it "runs rubocop as the lint job, hung off fast-lane" do
      lint = jobs.fetch("lint")
      commands = lint["steps"].filter_map { |s| s["run"] }
      expect(commands).to include("bundle exec rubocop")
      expect(jobs.fetch("fast-lane")["needs"]).to include("lint")
    end

    it "limits the Chromium workaround to the oracle canary step" do
      expected = [{ "SIRENA_ORACLE_CI_CANARY_NO_SANDBOX" => "1" }, nil]

      expect(oracle_browser_scope(jobs)).to eq(expected)
    end

    it "has no standalone lint workflow file any more" do
      basenames = workflow_files.map { |f| File.basename(f) }
      expect(basenames).not_to include("lint.yml")
    end

    it "keeps tests-passed without a tag-triggered release cascade" do
      steps = jobs.fetch("cascade").fetch("steps")

      expect(cascade_values(steps)).to eq([["Dispatch tests-passed"], false])
    end
  end

  describe "release.yml ownership" do
    def jobs
      release.fetch("jobs")
    end

    it "accepts only a manual workflow dispatch" do
      triggers = release["on"] || release[true]

      expect(triggers.keys).to eq(["workflow_dispatch"])
    end

    it "checks the changelog against the requested version" do
      expected = ['ruby scripts/check_changelog.rb "$NEXT_VERSION"',
                  "${{ inputs.next_version }}"]

      expect(changelog_values(changelog_step(jobs))).to eq(expected)
    end

    it "requires the changelog preflight before the repository-owned release" do
      expect(release_requirement_values(jobs)).to eq([["preflight"], nil])
    end

    it "requires the exact checked main head before preparing a release" do
      expect(checked_main_values(jobs)).to eq([true, true, true])
    end

    it "permits only a version change before an atomic push" do
      expect(version_push_values(jobs)).to eq([true, true])
    end

    it "builds and publishes the gem without a reusable release workflow" do
      expect(published_gem_values(jobs))
        .to eq(expected_published_gem_values)
    end
  end
end
