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

  let(:path) { "docs/history/completed-plans/04-svg-conform-gate.md" }
  let(:base) { sh(Dir.pwd, "git", "rev-parse", "HEAD") }

  around do |example|
    previous_base = ENV.fetch("COVERAGE_BASE", nil)
    Dir.mktmpdir("completed-plan-deletions") do |directory|
      Dir.chdir(directory) { example.run }
    end
  ensure
    ENV["COVERAGE_BASE"] = previous_base
  end

  before do
    sh(Dir.pwd, "git", "init", "-q", "-b", "main")
    sh(Dir.pwd, "git", "config", "user.name", "completed-plans")
    sh(Dir.pwd, "git", "config", "user.email", "plans@example.com")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(".gitignore", "coverage/\ntmp/\n")
    File.write(path, "# completed plan\n")
    sh(Dir.pwd, "git", "add", "-A")
    sh(Dir.pwd, "git", "commit", "-q", "-m", "base")
  end

  def delete_from_base
    original_base = base
    sh(Dir.pwd, "git", "rm", path)
    original_base
  end

  def deletion_check
    original_base = delete_from_base
    described_class.ensure_safe_deletions!(
      described_class.changed_paths(original_base), original_base
    )
  end

  def write_fresh_report
    FileUtils.mkdir_p("coverage")
    File.write("coverage/coverage.json", JSON.generate("coverage" => {}))
    stamp = Time.now + 5
    File.utime(stamp, stamp, "coverage/coverage.json")
  end

  def commit_executable
    sh(Dir.pwd, "git", "config", "core.filemode", "false")
    sh(Dir.pwd, "git", "update-index", "--chmod=+x", path)
    sh(Dir.pwd, "git", "commit", "-q", "-m", "executable")
  end

  def commit_symlink
    File.unlink(path)
    File.symlink("missing", path)
    sh(Dir.pwd, "git", "add", "-A")
    sh(Dir.pwd, "git", "commit", "-q", "-m", "symlink")
  end

  it "allows historical static Markdown deletion with the100 percent floor" do
    ENV["COVERAGE_BASE"] = delete_from_base
    write_fresh_report

    expect(described_class.command).to include("--minimum", "100")
  end

  {
    "active plan" => "TODO.foundation/04-svg-conform-gate.md",
    "ordinary documentation" => "docs/current.md",
    "spec" => "spec/current_spec.rb",
    "nested archive" => "docs/history/completed-plans/nested/current.md",
    "non-Markdown archive" => "docs/history/completed-plans/current.rb",
  }.each do |description, deleted_path|
    context "with a deleted #{description}" do
      let(:path) { deleted_path }

      it "retains the deletion failure" do
        expect { deletion_check }.to raise_error(/deleted vs COVERAGE_BASE/)
      end
    end
  end

  it "refuses historical Git executable mode even with core.filemode false" do
    commit_executable

    expect { deletion_check }.to raise_error(/deleted vs COVERAGE_BASE/)
  end

  it "refuses a historical symlink" do
    commit_symlink

    expect { deletion_check }.to raise_error(/deleted vs COVERAGE_BASE/)
  end
end
