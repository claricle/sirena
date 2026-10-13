# frozen_string_literal: true

require "spec_helper"
require "open3"
require "json"
require_relative "../../tasks/support/spec_shard"

RSpec.describe Sirena::SpecShard, :aggregate_failures do
  let(:unit_files) do
    (Dir.glob("spec/**{,/*/**}/*_spec.rb") -
      Dir.glob("spec/benchmarks/**/*_spec.rb")).uniq.sort
  end
  let(:script) do
    <<~RUBY
      require "rake"
      require "rspec/core"
      require "rspec/core/rake_task"
      require "shellwords"
      require "json"
      $0 = "rspec"
      captures = []
      RSpec::Core::RakeTask.define_method(:run_task) do |*|
        command = Shellwords.split(spec_command)
        arguments = command.drop(command.index { |word| word.end_with?("/rspec") } + 1)
        configuration = RSpec::Core::Configuration.new
        RSpec::Core::ConfigurationOptions.new(arguments).configure(configuration)
        captures << configuration.files_to_run.map { |path| path.delete_prefix(Dir.pwd + "/") }.sort
      end
      load "Rakefile"
      task = ARGV.fetch(0)
      if task == "bare"
        configuration = RSpec::Core::Configuration.new
        RSpec::Core::ConfigurationOptions.new([]).configure(configuration)
        captures << configuration.files_to_run.map { |path| path.delete_prefix(Dir.pwd + "/") }.sort
      else
        Rake::Task[task].invoke
      end
      puts JSON.generate(files: captures.flatten, tail: Rake::Task[:default].prerequisites)
    RUBY
  end

  let(:arguments) { ["benchmark"] }
  let(:shard) { nil }
  let(:result) do
    # This child inspects discovery without running examples; keep its load
    # outside the parent suite's coverage report.
    output, error, status = Open3.capture3(
      { "SIRENA_SPEC_SHARD" => shard, "COVERAGE" => nil },
      RbConfig.ruby, "-rbundler/setup",
      "-e", script, *arguments, chdir: File.expand_path("../..", __dir__)
    )
    raise error unless status.success?

    JSON.parse(output)
  end

  shared_examples "unit discovery" do |task|
    let(:arguments) { [task] }

    it "runs every ordinary spec and no benchmark" do
      expect(result.fetch("files")).to eq(unit_files)
    end
  end

  context "with bare RSpec" do
    it_behaves_like "unit discovery", "bare"
  end

  context "with the ordinary Rake task" do
    it_behaves_like "unit discovery", "spec"
  end

  context "with the coverage unit task" do
    it_behaves_like "unit discovery", "spec:unit"
  end

  it "selects every benchmark despite the ordinary exclusion" do
    expect(result.fetch("files")).to eq(
      ["spec/benchmarks/sirena/parser/flowchart_subgraph_benchmark_spec.rb"],
    )
  end

  it "keeps the benchmark in the default tail" do
    expect(result.fetch("tail")).to eq(
      %w[spec benchmark corpus:check claims_manifest:check layout_parity:check],
    )
  end

  context "with the final shard" do
    let(:shard) { "3/3" }

    it "keeps the complete default tail" do
      expect(result.fetch("tail")).to eq(
        %w[spec benchmark corpus:check claims_manifest:check
           layout_parity:check],
      )
    end
  end

  context "with an earlier shard" do
    let(:shard) { "1/3" }
    let(:arguments) { ["spec"] }

    it "runs its ordinary files without the benchmark or tail" do
      expect(result.fetch("files")).to eq(described_class.new(1, 3).files)
      expect(result.fetch("tail")).to eq(["spec"])
    end
  end
end
