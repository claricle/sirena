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

  let(:old_path) { "TODO.foundation/04-svg-conform-gate.md" }
  let(:new_path) { "docs/history/completed-plans/04-svg-conform-gate.md" }
  let(:content) { "# completed plan\n\nOriginal acceptance criteria.\n" }
  let(:base) { sh(Dir.pwd, "git", "rev-parse", "HEAD") }

  around do |example|
    previous_base = ENV.fetch("COVERAGE_BASE", nil)
    Dir.mktmpdir("plan-archives") do |directory|
      Dir.chdir(directory) { example.run }
    end
  ensure
    ENV["COVERAGE_BASE"] = previous_base
  end

  before do
    sh(Dir.pwd, "git", "init", "-q", "-b", "main")
    sh(Dir.pwd, "git", "config", "user.name", "plan-archives")
    sh(Dir.pwd, "git", "config", "user.email", "plans@example.com")
    FileUtils.mkdir_p(File.dirname(old_path))
    File.write(".gitignore", "coverage/\ntmp/\n")
    File.write(old_path, content)
    sh(Dir.pwd, "git", "add", "-A")
    sh(Dir.pwd, "git", "commit", "-q", "-m", "base")
    base
    FileUtils.mkdir_p(File.dirname(new_path))
    sh(Dir.pwd, "git", "mv", old_path, new_path)
  end

  it "accepts a staged byte-identical static plan archive" do
    expect(described_class.changed_paths(base)).to eq([new_path])
  end

  it "accepts a committed archive despite disabled ambient rename detection" do
    sh(Dir.pwd, "git", "config", "diff.renames", "false")
    sh(Dir.pwd, "git", "commit", "-q", "-m", "archive")

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

    it "passes the deletion check with the changed-line floor still100" do
      expect(described_class.command).to eq(
        ["bundle", "exec", "simplecov", "patch", "--input",
         "tmp/coverage-line-only.json", "--base", base, "--find-renames",
         "--minimum", "100"],
      )
    end
  end

  %w[R099 C100].each do |status|
    it "refuses #{status} rather than trusting an edited move or copy" do
      expect(described_class.identical_plan_archive?(
               status, [old_path, new_path], base
             )).to be(false)
    end
  end

  it "preserves the deletion failure for an edited archive" do
    File.write(new_path, "#{content}Edited acceptance criteria.\n")
    paths = described_class.changed_paths(base)

    expect { described_class.ensure_safe_deletions!(paths, base) }
      .to raise_error(/#{Regexp.escape(old_path)} deleted/)
  end

  {
    "an arbitrary docs directory" => "docs/04-svg-conform-gate.md",
    "a nested archive" => "docs/history/completed-plans/nested/" \
                          "04-svg-conform-gate.md",
    "a changed basename" => "docs/history/completed-plans/other.md",
    "Ruby source" => "lib/04-svg-conform-gate.rb",
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

  context "with an ordinary Markdown source" do
    let(:old_path) { "spec/fixtures/04-svg-conform-gate.md" }

    it "refuses archiving a potential executable fixture" do
      expect(described_class.changed_paths(base)).to include(old_path)
    end
  end

  it "refuses a destination removed after staging" do
    File.unlink(new_path)

    expect(described_class.changed_paths(base)).to include(old_path)
  end

  it "preserves the deletion failure if the archive is deleted outright" do
    File.unlink(new_path)
    sh(Dir.pwd, "git", "add", "-A")
    paths = described_class.changed_paths(base)

    expect { described_class.ensure_safe_deletions!(paths, base) }
      .to raise_error(/#{Regexp.escape(old_path)} deleted/)
  end

  it "refuses an executable destination" do
    File.chmod(0o755, new_path)

    expect(described_class.changed_paths(base)).to include(old_path)
  end

  it "refuses a symlink destination" do
    File.unlink(new_path)
    File.symlink("missing", new_path)

    expect(described_class.changed_paths(base)).to include(old_path)
  end

  it "refuses a destination beneath a symlink directory" do
    FileUtils.mv("docs/history/completed-plans", "elsewhere")
    File.symlink("../../elsewhere", "docs/history/completed-plans")

    expect(described_class.changed_paths(base)).to include(old_path)
  end

  context "with an executable source" do
    let(:executable_base) { sh(Dir.pwd, "git", "rev-parse", "HEAD") }

    before do
      sh(Dir.pwd, "git", "reset", "--hard", base)
      File.chmod(0o755, old_path)
      sh(Dir.pwd, "git", "add", "-A")
      sh(Dir.pwd, "git", "commit", "-q", "-m", "executable")
      executable_base
      FileUtils.mkdir_p(File.dirname(new_path))
      sh(Dir.pwd, "git", "mv", old_path, new_path)
      File.chmod(0o644, new_path)
    end

    it "retains the source deletion despite removing executable permissions" do
      paths = described_class.changed_paths(executable_base)

      expect(paths).to include(old_path)
    end
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
      expect(described_class.changed_paths(symlink_base)).to include(old_path)
    end
  end
end
