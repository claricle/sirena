# frozen_string_literal: true

require "spec_helper"
require "rake"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

# `load` defines CoverageTasks; a private application keeps the tasks it
# declares out of whatever Rake.application the suite is running under.
Rake.with_application(Rake::Application.new) do
  load File.expand_path("../tasks/coverage.rake", __dir__)
end

# Real throwaway Git repositories drive `coverage:changed_lines`, so what is
# asserted is what Git itself reports for each move, not a stubbed diff. The
# changed-line gate's final `sh` is stubbed on the top-level object, which is
# the receiver of the rake block (the file is loaded without `wrap:`).
module CoverageSpecMoveHelpers
  include GitRepoHelpers

  def base_spec = "spec/alpha/foo_spec.rb"

  def spec_content
    "RSpec.describe('Foo') { it('works') { expect(1).to eq(1) } }\n"
  end

  def git!(*)
    sh(Dir.pwd, "git", *)
  end

  def init_repo!
    git! "init", "-q", "-b", "main"
    git! "config", "user.email", "coverage-moves@example.com"
    git! "config", "user.name", "coverage-moves"
  end

  def write_file(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  # Commits lib/foo.rb (with coverage/ and tmp/ ignored, as in this repo)
  # plus the given files and returns the base sha.
  def commit_base!(files = { base_spec => spec_content })
    write_file(".gitignore", "coverage/\ntmp/\n")
    write_file("lib/foo.rb", "class Foo\nend\n")
    files.each { |path, content| write_file(path, content) }
    git! "add", "-A"
    git! "commit", "-q", "-m", "base"
    git! "rev-parse", "HEAD"
  end

  # A base whose spec is a symlink: moving it is a rename Git calls R100.
  def commit_symlinked_spec!
    write_file("spec/real.txt", "real\n")
    FileUtils.mkdir_p("spec/alpha")
    File.symlink("../real.txt", "spec/alpha/link_spec.rb")
    commit_base!
  end

  def move!(from, to)
    FileUtils.mkdir_p(File.dirname(to))
    git! "mv", from, to
  end

  def commit_all!
    git! "add", "-A"
    git! "commit", "-q", "-m", "change"
  end

  # Commits the working tree, then leaves a report newer than all of it.
  def finish!
    commit_all!
    write_fresh_report!
  end

  # A report that is newer than every file and whose lib source matches, as
  # `rake coverage:measure` leaves it.
  def write_fresh_report!(manifest: nil)
    lines = File.readlines("lib/foo.rb", chomp: true)
    FileUtils.mkdir_p("coverage")
    entry = { "source" => lines, "lines" => [1, 1, 1] }
    report = { "coverage" => { "lib/foo.rb" => entry } }
    File.write("coverage/coverage.json", JSON.generate(report))
    write_manifest!(manifest) if manifest
    stamp = Time.now + 5
    File.utime(stamp, stamp, "coverage/coverage.json")
  end

  def write_manifest!(manifest)
    FileUtils.mkdir_p("tmp")
    File.write("tmp/coverage-source-manifest.json", JSON.generate(manifest))
  end

  def digest(path)
    Digest::SHA256.file(path).hexdigest
  end

  def main_object
    TOPLEVEL_BINDING.receiver
  end

  def invoke!
    Rake::Task["coverage:changed_lines"].invoke
  end

  def expect_gate_passed!(base)
    expect { invoke! }.not_to raise_error
    expect(main_object).to have_received(:sh).with(
      "bundle", "exec", "simplecov", "patch", "--input",
      "tmp/coverage-line-only.json", "--base", base, "--find-renames",
      "--minimum", "100"
    )
  end

  def expect_deletion_refused!(*paths)
    listed = paths.map { |path| Regexp.escape(path) }.join(", ")

    expect { invoke! }.to raise_error(/#{listed} deleted vs COVERAGE_BASE=/)
    expect(main_object).not_to have_received(:sh)
  end
end

RSpec.describe CoverageTasks, :aggregate_failures do
  include CoverageSpecMoveHelpers

  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    load File.expand_path("../tasks/coverage.rake", __dir__)
    previous = ENV.to_h.slice("COVERAGE_BASE", "COVERAGE")

    Dir.mktmpdir("coverage-spec-moves") do |dir|
      Dir.chdir(dir) { example.run }
    end
  ensure
    Rake.application = original_application
    %w[COVERAGE_BASE COVERAGE].each { |key| ENV[key] = previous[key] }
  end

  before { allow(main_object).to receive(:sh) }

  describe "a byte-identical move between discovered spec paths" do
    let!(:base) do
      init_repo!
      commit_base!.tap { ENV["COVERAGE_BASE"] = _1 }
    end

    it "passes once committed, after a fresh report" do
      move!(base_spec, "spec/beta/gamma/foo_spec.rb")
      finish!

      expect_gate_passed!(base)
    end

    it "passes when staged but not yet committed" do
      move!(base_spec, "spec/foo_spec.rb")
      write_fresh_report!

      expect_gate_passed!(base)
    end

    # The reproduced failure: with rename detection off, Git reports the same
    # move as a deletion plus an addition and the old guard refused it.
    it "passes even when the ambient git config disables rename detection" do
      git! "config", "diff.renames", "false"
      move!(base_spec, "spec/beta/foo_spec.rb")
      finish!

      expect_gate_passed!(base)
    end

    it "still requires the moved file to be in the measure-time manifest" do
      move!(base_spec, "spec/beta/foo_spec.rb")
      commit_all!
      write_fresh_report!(manifest: { "lib/foo.rb" => digest("lib/foo.rb") })

      expect { invoke! }
        .to raise_error(%r{predates a newer edit to spec/beta/foo_spec\.rb})
    end

    it "passes when the manifest records the moved file" do
      move!(base_spec, "spec/beta/foo_spec.rb")
      commit_all!
      moved = "spec/beta/foo_spec.rb"
      write_fresh_report!(manifest: { moved => digest(moved) })

      expect_gate_passed!(base)
    end

    context "when the same change also deletes another spec" do
      let(:other) { "spec/alpha/other_spec.rb" }

      before do
        write_file(other, "# other\n")
        git! "add", "-A"
        git! "commit", "-q", "-m", "other"
        ENV["COVERAGE_BASE"] = git!("rev-parse", "HEAD")
      end

      it "still refuses the unrelated deletion" do
        move!(base_spec, "spec/beta/foo_spec.rb")
        git! "rm", "-q", other
        finish!

        expect_deletion_refused!(other)
      end
    end
  end

  describe "a move that is not a verified identical spec rename" do
    before { init_repo! }

    context "with the spec in the base commit" do
      before { ENV["COVERAGE_BASE"] = commit_base! }

      it "refuses an edited rename" do
        move!(base_spec, "spec/beta/foo_spec.rb")
        File.write("spec/beta/foo_spec.rb", "#{spec_content}# edited\n")
        finish!

        expect_deletion_refused!(base_spec)
      end

      {
        "to a path without the _spec.rb suffix" => "spec/beta/foo_helper.rb",
        "to a path outside spec/" => "lib/foo_spec.rb",
        "to a hidden directory the default pattern skips" =>
          "spec/.hidden/foo_spec.rb",
        "to a path that only starts like a spec suffix" =>
          "spec/beta/foo_spec.rb.bak",
      }.each do |description, target|
        it "refuses a move #{description}" do
          move!(base_spec, target)
          finish!

          expect_deletion_refused!(base_spec)
        end
      end

      it "refuses a replacement that is missing from the working tree" do
        move!(base_spec, "spec/beta/foo_spec.rb")
        FileUtils.rm("spec/beta/foo_spec.rb")
        write_fresh_report!

        expect_deletion_refused!(base_spec)
      end

      it "refuses an ordinary deletion of a spec file" do
        git! "rm", "-q", base_spec
        finish!

        expect_deletion_refused!(base_spec)
      end

      it "refuses an unstaged move, which Git cannot verify as a rename" do
        FileUtils.mkdir_p("spec/beta")
        FileUtils.mv(base_spec, "spec/beta/foo_spec.rb")
        write_fresh_report!

        expect_deletion_refused!(base_spec)
      end
    end

    it "refuses moving a non-spec file into spec/" do
      ENV["COVERAGE_BASE"] = commit_base!("scripts/tool_spec.rb" => "# t\n")
      move!("scripts/tool_spec.rb", "spec/beta/tool_spec.rb")
      finish!

      expect_deletion_refused!("scripts/tool_spec.rb")
    end

    it "refuses moving the Rakefile" do
      ENV["COVERAGE_BASE"] = commit_base!("Rakefile" => "task :x\n")
      move!("Rakefile", "spec/beta/rakefile_spec.rb")
      finish!

      expect_deletion_refused!("Rakefile")
    end

    it "refuses a move whose replacement is a symlink" do
      ENV["COVERAGE_BASE"] = commit_symlinked_spec!
      move!("spec/alpha/link_spec.rb", "spec/beta/link_spec.rb")
      finish!

      expect_deletion_refused!("spec/alpha/link_spec.rb")
    end
  end

  describe "git failures" do
    before do
      init_repo!
      commit_base!
      write_fresh_report!
      ENV["COVERAGE_BASE"] = "no-such-ref"
    end

    it "fail closed instead of treating the diff as empty" do
      expect { invoke! }.to raise_error(/no-such-ref failed/)
      expect(main_object).not_to have_received(:sh)
    end
  end
end
