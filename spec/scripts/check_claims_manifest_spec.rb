# frozen_string_literal: true

require_relative "../../scripts/check_claims_manifest"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

# Builds a real throwaway git repository so `.problems` exercises the actual
# `git grep` invocation against tracked/untracked/excluded content, not a
# mock of it.
module ClaimsManifestFixture
  def git_repo(files)
    Dir.mktmpdir do |dir|
      Open3.capture3("git", "-C", dir, "init", "-q")
      Open3.capture3("git", "-C", dir, "config", "user.email", "t@example.com")
      Open3.capture3("git", "-C", dir, "config", "user.name", "t")
      files.each do |path, content|
        full = File.join(dir, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, content)
      end
      Open3.capture3("git", "-C", dir, "add", "-A")
      Open3.capture3("git", "-C", dir, "commit", "-q", "-m", "seed")
      yield dir
    end
  end

  def manifest_yaml(rows)
    rows.to_yaml
  end

  def write_manifest(root, rows)
    path = File.join(root, "docs/claims-manifest.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, rows.to_yaml)
    Open3.capture3("git", "-C", root, "add", "-A")
    Open3.capture3("git", "-C", root, "commit", "-q", "-m", "manifest")
  end

  def install_script(root)
    FileUtils.mkdir_p(File.join(root, "scripts"))
    FileUtils.cp(File.expand_path("../../scripts/check_claims_manifest.rb", __dir__),
                 File.join(root, "scripts"))
  end
end

RSpec.describe Sirena::ClaimsManifestCheck do
  include ClaimsManifestFixture

  let(:removed_row) do
    { "claim" => "16x faster batch processing", "file" => "docs/x.adoc",
      "disposition" => "removed", "evidence" => "git grep -F ...", "pr" => 106 }
  end
  let(:corrected_row) do
    { "claim" => "19 diagram types", "file" => "docs/x.adoc",
      "disposition" => "corrected", "evidence" => "ruby -e ...", "pr" => 106 }
  end
  let(:verified_row) do
    { "claim" => "benchmark rake tasks run to completion", "file" => "tasks/benchmark.rake",
      "disposition" => "verified", "evidence" => "bundle exec rspec ...", "pr" => 131 }
  end

  describe ".rows" do
    it "parses a well-formed manifest" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "manifest.yml")
        File.write(path, manifest_yaml([removed_row]))
        expect(described_class.rows(path)).to eq([removed_row])
      end
    end

    it "rejects a document that is not a list" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "manifest.yml")
        File.write(path, { "claim" => "x" }.to_yaml)
        expect { described_class.rows(path) }.to raise_error(ArgumentError, /list of rows/)
      end
    end

    Sirena::ClaimsManifestCheck::REQUIRED_KEYS.each do |key|
      it "rejects a row missing the required key #{key.inspect}" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "manifest.yml")
          bad = removed_row.except(key)
          File.write(path, manifest_yaml([bad]))
          expect { described_class.rows(path) }.to raise_error(ArgumentError, /missing #{key}/)
        end
      end
    end

    it "rejects an unknown disposition" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "manifest.yml")
        bad = removed_row.merge("disposition" => "maybe")
        File.write(path, manifest_yaml([bad]))
        expect { described_class.rows(path) }.to raise_error(ArgumentError, /disposition/)
      end
    end

    it "rejects a row whose claim is not a string" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "manifest.yml")
        bad = removed_row.merge("claim" => 12_345)
        File.write(path, manifest_yaml([bad]))
        expect { described_class.rows(path) }.to raise_error(ArgumentError, /claim must be string/)
      end
    end

    it "rejects a row whose pr is not an Integer" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "manifest.yml")
        bad = removed_row.merge("pr" => "106")
        File.write(path, manifest_yaml([bad]))
        expect { described_class.rows(path) }.to raise_error(ArgumentError, /pr must be an Integer/)
      end
    end

    it "rejects a claim containing a newline" do
      # git grep -F -e treats an embedded newline as a break between separate
      # OR'd patterns rather than a literal character in one pattern, so an
      # unchecked multi-line claim would silently change what "present" means.
      Dir.mktmpdir do |dir|
        path = File.join(dir, "manifest.yml")
        bad = removed_row.merge("claim" => "line one\nline two")
        File.write(path, manifest_yaml([bad]))
        expect { described_class.rows(path) }.to raise_error(ArgumentError, /must not contain a newline/)
      end
    end
  end

  describe ".problems" do
    it "is clean when a removed claim is genuinely absent everywhere" do
      git_repo("README.adoc" => "nothing relevant here\n") do |root|
        write_manifest(root, [removed_row])
        expect(described_class.problems(root: root)).to eq([])
      end
    end

    it "flags a removed claim that still appears in a tracked, non-excluded file" do
      git_repo("README.adoc" => "we are 16x faster batch processing today\n") do |root|
        write_manifest(root, [removed_row])
        found = described_class.problems(root: root)
        expect(found.size).to eq(1)
        expect(found.first).to include("16x faster batch processing")
      end
    end

    it "ignores a removed claim's own surviving text inside docs/plans/" do
      git_repo("docs/plans/notes.md" => "we removed \"16x faster batch processing\"\n") do |root|
        write_manifest(root, [removed_row])
        expect(described_class.problems(root: root)).to eq([])
      end
    end

    it "ignores a removed claim's own surviving text inside TODO.foundation/" do
      git_repo("TODO.foundation/11.md" => "16x faster batch processing was false\n") do |root|
        write_manifest(root, [removed_row])
        expect(described_class.problems(root: root)).to eq([])
      end
    end

    it "ignores a removed claim quoted only inside the manifest file itself" do
      git_repo({}) do |root|
        write_manifest(root, [removed_row])
        # the manifest necessarily contains its own claim text
        expect(described_class.problems(root: root)).to eq([])
      end
    end

    it "ignores a removed claim present only in an untracked file" do
      git_repo("README.adoc" => "clean\n") do |root|
        write_manifest(root, [removed_row])
        File.write(File.join(root, "untracked.md"), "16x faster batch processing\n")
        expect(described_class.problems(root: root)).to eq([])
      end
    end

    it "never checks a corrected row against tracked source" do
      git_repo("README.adoc" => "19 diagram types, still here on purpose\n") do |root|
        write_manifest(root, [corrected_row])
        expect(described_class.problems(root: root)).to eq([])
      end
    end

    it "never checks a verified row against tracked source" do
      git_repo("README.adoc" => "benchmark rake tasks run to completion, on purpose\n") do |root|
        write_manifest(root, [verified_row])
        expect(described_class.problems(root: root)).to eq([])
      end
    end

    it "ignores a removed claim's own surviving text inside _site/" do
      git_repo("_site/index.html" => "16x faster batch processing\n") do |root|
        write_manifest(root, [removed_row])
        expect(described_class.problems(root: root)).to eq([])
      end
    end

    it "ignores a removed claim's own surviving text inside this checker's own spec file" do
      # a bare "." pathspec otherwise means this checker's own fixture text
      # counts as "evidence" the claim is still present -- CLAIMS_MANIFEST_SPEC_RELPATH
      # excludes it the same way docs/plans, TODO.foundation, and _site are excluded above.
      git_repo("spec/scripts/check_claims_manifest_spec.rb" => "# fixture: 16x faster batch processing\n") do |root|
        write_manifest(root, [removed_row])
        expect(described_class.problems(root: root)).to eq([])
      end
    end
  end

  describe ".present_in_tracked_source?" do
    it "raises a named error, not a bare RuntimeError, when git grep itself fails" do
      Dir.mktmpdir do |root|
        # a plain tmpdir is not a git repository, so `git -C root grep` exits
        # 128 ("not a git repository") rather than 0 (match) or 1 (no match)
        expect do
          described_class.present_in_tracked_source?("anything", root)
        end.to raise_error(described_class::GitGrepError, /git grep failed/)
      end
    end
  end

  describe ".report!" do
    # report! is required directly by this very spec file (line 3), so it is
    # library code that a caller can invoke in-process -- it must return a
    # status rather than calling exit/abort itself, or requiring this file
    # for its constants/helpers would risk killing the RSpec process. Only
    # the `if __FILE__ == $PROGRAM_NAME` guard and tasks/claims_manifest.rake
    # may translate the boolean into an actual exit.
    #
    # `expect { ... }.to output(...).to_stdout`/`.to_stderr` does NOT prove
    # this on its own: `exit`/`abort` raise SystemExit, which unwinds straight
    # through that matcher and out of RSpec's own example runner, killing the
    # process before the assertion below it is ever checked -- reproduced by
    # mutating report! to call `exit(0)` on the clean path and watching the
    # suite silently stop after this example (0 failures) instead of failing
    # it. Stubbing exit/abort as no-ops and asserting `not_to have_received`
    # intercepts the call itself before it can actually exit.
    it "returns true and prints 'clean', without calling exit or abort, when nothing is wrong" do
      git_repo("README.adoc" => "clean\n") do |root|
        write_manifest(root, [removed_row])
        allow(described_class).to receive(:exit)
        allow(described_class).to receive(:abort)
        result = nil
        expect { result = described_class.report!(root: root) }.to output(/claims manifest: clean/).to_stdout
        expect(described_class).not_to have_received(:exit)
        expect(described_class).not_to have_received(:abort)
        expect(result).to be(true)
      end
    end

    it "returns false, without calling exit or abort, when a removed claim survives" do
      git_repo("README.adoc" => "we are 16x faster batch processing today\n") do |root|
        write_manifest(root, [removed_row])
        allow(described_class).to receive(:exit)
        allow(described_class).to receive(:abort)
        result = nil
        expect { result = described_class.report!(root: root) }
          .to output(/16x faster batch processing/).to_stderr
        expect(described_class).not_to have_received(:exit)
        expect(described_class).not_to have_received(:abort)
        expect(result).to be(false)
      end
    end

    it "returns false, without calling exit or abort, when the manifest itself is malformed" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "docs"))
        File.write(File.join(dir, "docs/claims-manifest.yml"), { "claim" => "x" }.to_yaml)
        allow(described_class).to receive(:exit)
        allow(described_class).to receive(:abort)
        result = nil
        expect { result = described_class.report!(root: dir) }.to output(/list of rows/).to_stderr
        expect(described_class).not_to have_received(:exit)
        expect(described_class).not_to have_received(:abort)
        expect(result).to be(false)
      end
    end
  end

  describe "command line" do
    def run_script(root)
      script = File.expand_path("scripts/check_claims_manifest.rb", root)
      Open3.capture3(RbConfig.ruby, script, chdir: root)
    end

    it "exits 0 when every removed claim is absent" do
      git_repo("README.adoc" => "clean\n") do |root|
        install_script(root)
        write_manifest(root, [removed_row])
        _out, _err, status = run_script(root)
        expect(status.exitstatus).to eq(0)
      end
    end

    it "exits 1 and names the claim when a removed claim survives" do
      git_repo("README.adoc" => "we are 16x faster batch processing today\n") do |root|
        install_script(root)
        write_manifest(root, [removed_row])
        _out, err, status = run_script(root)
        expect(status.exitstatus).to eq(1)
        expect(err).to include("16x faster batch processing")
      end
    end

    it "exits 1 with a readable message, not a backtrace, on a malformed manifest" do
      git_repo({}) do |root|
        install_script(root)
        FileUtils.mkdir_p(File.join(root, "docs"))
        File.write(File.join(root, "docs/claims-manifest.yml"), { "claim" => "x" }.to_yaml)
        _out, err, status = run_script(root)
        expect(status.exitstatus).to eq(1)
        expect(err).to include("list of rows")
      end
    end

    it "exits 1 with a readable message when a manifest row is missing a required key" do
      git_repo({}) do |root|
        install_script(root)
        write_manifest(root, [removed_row.except("evidence")])
        _out, err, status = run_script(root)
        expect(status.exitstatus).to eq(1)
        expect(err).to include("missing evidence")
      end
    end

    it "exits 1 with a readable message, not a backtrace, on unparseable YAML" do
      git_repo({}) do |root|
        install_script(root)
        FileUtils.mkdir_p(File.join(root, "docs"))
        File.write(File.join(root, "docs/claims-manifest.yml"), "this: is: not: valid: yaml: [\n")
        _out, err, status = run_script(root)
        expect(status.exitstatus).to eq(1)
        expect(err).to include("claims manifest check failed:")
        expect(err.lines.size).to eq(1)
      end
    end

    it "exits 1 with a readable message, not a backtrace, when git grep itself fails" do
      Dir.mktmpdir do |root|
        # a plain tmpdir, never `git init`'d, so `report!`'s internal git-grep
        # call fails rather than returning a match/no-match verdict
        install_script(root)
        FileUtils.mkdir_p(File.join(root, "docs"))
        File.write(File.join(root, "docs/claims-manifest.yml"), [removed_row].to_yaml)
        _out, err, status = run_script(root)
        expect(status.exitstatus).to eq(1)
        # A rescued failure prints exactly this one prefixed line; an
        # uncaught exception instead prints a multi-line Ruby backtrace
        # (several "from ...:in '...'" lines) that never contains it.
        expect(err).to include("claims manifest check failed: git grep failed")
        expect(err.lines.size).to eq(1)
      end
    end
  end
end
