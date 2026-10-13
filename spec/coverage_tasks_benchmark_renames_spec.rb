# frozen_string_literal: true

require "spec_helper"
require "rake"
require "tmpdir"
require "fileutils"
require "json"

Rake.with_application(Rake::Application.new) do
  load File.expand_path("../tasks/coverage.rake", __dir__)
end

RSpec.describe CoverageTasks do
  include GitRepoHelpers

  let(:old_path) { "spec/benchmarks/flowchart_subgraph_benchmark.rb" }
  let(:new_path) do
    "spec/benchmarks/sirena/parser/flowchart_subgraph_benchmark_spec.rb"
  end
  let(:content) { "RSpec.describe('benchmark') { it('times parsing') {} }\n" }
  let(:base) { sh(Dir.pwd, "git", "rev-parse", "HEAD") }

  around do |example|
    previous_base = ENV.fetch("COVERAGE_BASE", nil)
    Dir.mktmpdir("benchmark-moves") do |directory|
      Dir.chdir(directory) { example.run }
    end
  ensure
    ENV["COVERAGE_BASE"] = previous_base
  end

  before do
    sh(Dir.pwd, "git", "init", "-q", "-b", "main")
    sh(Dir.pwd, "git", "config", "user.name", "benchmark-moves")
    sh(Dir.pwd, "git", "config", "user.email", "benchmark@example.com")
    FileUtils.mkdir_p(File.dirname(old_path))
    File.write(".gitignore", "coverage/\ntmp/\n")
    File.write(old_path, content)
    sh(Dir.pwd, "git", "add", "-A")
    sh(Dir.pwd, "git", "commit", "-q", "-m", "base")
    base
    FileUtils.mkdir_p(File.dirname(new_path))
    sh(Dir.pwd, "git", "mv", old_path, new_path)
  end

  it "accepts a staged byte-identical move into benchmark discovery" do
    expect(described_class.changed_paths(base)).to eq([new_path])
  end

  it "accepts a committed move with ambient rename detection disabled" do
    sh(Dir.pwd, "git", "config", "diff.renames", "false")
    sh(Dir.pwd, "git", "commit", "-q", "-m", "move")

    expect(described_class.changed_paths(base)).to eq([new_path])
  end

  context "with a fresh coverage report" do
    before do
      ENV["COVERAGE_BASE"] = base
      FileUtils.mkdir_p("coverage")
      File.write("coverage/coverage.json", JSON.generate("coverage" => {}))
      stamp = Time.now + 5
      File.utime(stamp, stamp, "coverage/coverage.json")
    end

    it "passes the deletion check and retains the changed-line hard floor" do
      expect(described_class.command).to eq(
        ["bundle", "exec", "simplecov", "patch", "--input",
         "tmp/coverage-line-only.json", "--base", base, "--find-renames",
         "--minimum", "100"],
      )
    end

    it "requires the new path in a present measure-time manifest" do
      FileUtils.mkdir_p("tmp")
      File.write("tmp/coverage-source-manifest.json", "{}")

      expect { described_class.command }
        .to raise_error(/predates a newer edit to #{Regexp.escape(new_path)}/)
    end
  end

  %w[R099 C100].each do |status|
    it "refuses #{status} even between valid benchmark paths" do
      expect(described_class.identical_benchmark_move?(
               status, [old_path, new_path], base
             )).to be(false)
    end
  end

  it "preserves the deletion failure for an edited rename" do
    File.write(new_path, "#{content}# edited\n")
    paths = described_class.changed_paths(base)

    expect { described_class.ensure_safe_deletions!(paths, base) }
      .to raise_error(/#{Regexp.escape(old_path)} deleted/)
  end

  {
    "ordinary unit discovery" => "spec/sirena/parser/flowchart_spec.rb",
    "a hidden directory" => "spec/benchmarks/.hidden/flowchart_spec.rb",
    "a hidden filename" => "spec/benchmarks/.flowchart_spec.rb",
    "a non-spec suffix" => "spec/benchmarks/flowchart.rb",
    "the obsolete benchmark suffix" =>
      "spec/benchmarks/other_benchmark.rb",
    "outside benchmark discovery" => "lib/flowchart_benchmark_spec.rb",
  }.each do |description, target|
    context "with the destination in #{description}" do
      let(:new_path) { target }

      it "retains the original deletion in the coverage guard" do
        paths = described_class.changed_paths(base)

        expect { described_class.ensure_safe_deletions!(paths, base) }
          .to raise_error(/#{Regexp.escape(old_path)} deleted/)
      end
    end
  end

  context "with the source in ordinary unit discovery" do
    let(:old_path) { "spec/sirena/parser/flowchart_spec.rb" }

    it "refuses moving a unit spec into excluded benchmark discovery" do
      expect(described_class.changed_paths(base)).to include(old_path)
    end
  end

  context "with an already conventional benchmark source" do
    let(:old_path) { "spec/benchmarks/old_benchmark_spec.rb" }

    it "accepts a move within the same benchmark discovery boundary" do
      expect(described_class.changed_paths(base)).to eq([new_path])
    end
  end

  it "refuses a destination removed after staging" do
    File.unlink(new_path)

    expect(described_class.changed_paths(base)).to include(old_path)
  end

  it "refuses a symlink destination" do
    File.unlink(new_path)
    File.symlink("missing", new_path)

    expect(described_class.identical_benchmark_move?(
             "R100", [old_path, new_path], base
           )).to be(false)
  end

  it "refuses a destination beneath a symlink directory skipped by discovery" do
    FileUtils.mv("spec/benchmarks/sirena", "spec/elsewhere")
    File.symlink("../elsewhere", "spec/benchmarks/sirena")

    expect(described_class.identical_benchmark_move?(
             "R100", [old_path, new_path], base
           )).to be(false)
  end

  context "with a symlink source replaced by identical regular bytes" do
    let(:symlink_base) { sh(Dir.pwd, "git", "rev-parse", "HEAD") }

    before do
      sh(Dir.pwd, "git", "reset", "--hard", base)
      File.unlink(old_path)
      File.symlink("missing", old_path)
      sh(Dir.pwd, "git", "add", "-A")
      sh(Dir.pwd, "git", "commit", "-q", "-m", "symlink")
      symlink_base
      FileUtils.mkdir_p(File.dirname(new_path))
      sh(Dir.pwd, "git", "mv", old_path, new_path)
      File.unlink(new_path)
      File.write(new_path, "missing")
    end

    it "retains the source deletion" do
      expect(described_class.identical_benchmark_move?(
               "R100", [old_path, new_path], symlink_base
             )).to be(false)
    end
  end
end
