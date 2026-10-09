# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "spec_helper"
require "tmpdir"
require "yaml"
require_relative "../../scripts/check_claims_manifest"

module ClaimsManifestFixture
  include GitRepoHelpers

  def removed_row
    {
      "claim" => "16x faster batch processing",
      "file" => "docs/comparison.adoc",
      "disposition" => "removed",
      "evidence" => "ruby scripts/check_claims_manifest.rb",
      "pr" => 106,
    }
  end

  def decided_row(disposition)
    removed_row.merge("disposition" => disposition)
  end

  def git_repo(files = {})
    Dir.mktmpdir do |root|
      sh(root, "git", "init", "-q")
      sh(root, "git", "config", "user.email", "t@example.com")
      sh(root, "git", "config", "user.name", "t")
      files.each { |path, content| write_file(root, path, content) }
      sh(root, "git", "add", "-A")
      sh(root, "git", "commit", "-q", "-m", "seed") unless files.empty?
      yield root
    end
  end

  def write_file(root, path, content)
    full_path = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  def write_manifest(root, rows)
    write_file(root, "docs/claims-manifest.yml", rows.to_yaml)
    sh(root, "git", "add", "-A")
    sh(root, "git", "commit", "-q", "-m", "manifest")
  end

  def manifest_file(rows)
    Dir.mktmpdir do |root|
      path = File.join(root, "manifest.yml")
      File.write(path, rows.to_yaml)
      yield path
    end
  end

  def install_checker(root)
    source = File.expand_path("../../scripts/check_claims_manifest.rb", __dir__)
    FileUtils.mkdir_p(File.join(root, "scripts"))
    FileUtils.cp(source, File.join(root, "scripts"))
  end

  def command_status(root)
    command = [RbConfig.ruby, "scripts/check_claims_manifest.rb"]
    Open3.capture3(*command, chdir: root).last
  end
end

RSpec.describe Sirena::ClaimsManifestCheck do
  include ClaimsManifestFixture

  describe ".rows" do
    it "accepts a complete decided row" do
      manifest_file([removed_row]) do |path|
        expect(described_class.rows(path)).to eq([removed_row])
      end
    end

    it "rejects an empty manifest" do
      manifest_file([]) do |path|
        expect { described_class.rows(path) }
          .to raise_error(ArgumentError, /non-empty YAML list/)
      end
    end

    it "rejects a row missing a required key" do
      manifest_file([removed_row.except("evidence")]) do |path|
        expect { described_class.rows(path) }
          .to raise_error(ArgumentError, /missing evidence/)
      end
    end

    it "rejects an unknown key" do
      row = removed_row.merge("note" => "not part of the schema")
      manifest_file([row]) do |path|
        expect { described_class.rows(path) }
          .to raise_error(ArgumentError, /unknown keys note/)
      end
    end

    it "rejects blank evidence" do
      manifest_file([removed_row.merge("evidence" => "  ")]) do |path|
        expect { described_class.rows(path) }
          .to raise_error(ArgumentError, /evidence.*non-empty/)
      end
    end

    it "rejects an unresolved disposition" do
      row = removed_row.merge("disposition" => "unresolved")
      manifest_file([row]) do |path|
        expect { described_class.rows(path) }
          .to raise_error(ArgumentError, /disposition.*unresolved/)
      end
    end

    it "rejects a non-positive PR number" do
      manifest_file([removed_row.merge("pr" => 0)]) do |path|
        expect { described_class.rows(path) }
          .to raise_error(ArgumentError, /positive Integer/)
      end
    end

    it "rejects a multiline exact-match claim" do
      row = removed_row.merge("claim" => "line one\nline two")
      manifest_file([row]) do |path|
        expect { described_class.rows(path) }
          .to raise_error(ArgumentError, /must not contain a newline/)
      end
    end

    it "accepts the repository manifest as fully decided and clean" do
      root = File.expand_path("../..", __dir__)

      expect(described_class.problems(root: root)).to be_empty
    end
  end

  describe ".problems" do
    it "accepts a removed claim that is absent from tracked source" do
      git_repo("README.adoc" => "nothing relevant\n") do |root|
        write_manifest(root, [removed_row])
        expect(described_class.problems(root: root)).to be_empty
      end
    end

    it "flags a removed claim that returns to tracked source" do
      git_repo("README.adoc" => "16x faster batch processing\n") do |root|
        write_manifest(root, [removed_row])
        problem = described_class.problems(root: root).first
        expect(problem).to include(removed_row.fetch("claim"))
      end
    end

    it "ignores inventory evidence in an excluded plan" do
      files = { "docs/plans/inventory.md" => "16x faster batch processing\n" }
      git_repo(files) do |root|
        write_manifest(root, [removed_row])
        expect(described_class.problems(root: root)).to be_empty
      end
    end

    it "ignores generated site output" do
      git_repo("_site/index.html" => "16x faster batch processing\n") do |root|
        write_manifest(root, [removed_row])
        expect(described_class.problems(root: root)).to be_empty
      end
    end

    it "does not apply absence checks to corrected claims" do
      git_repo("README.adoc" => "16x faster batch processing\n") do |root|
        write_manifest(root, [decided_row("corrected")])
        expect(described_class.problems(root: root)).to be_empty
      end
    end

    it "does not apply absence checks to verified claims" do
      git_repo("README.adoc" => "16x faster batch processing\n") do |root|
        write_manifest(root, [decided_row("verified")])
        expect(described_class.problems(root: root)).to be_empty
      end
    end
  end

  describe ".report!" do
    it "returns true for a clean manifest" do
      git_repo("README.adoc" => "clean\n") do |root|
        write_manifest(root, [removed_row])
        expect(described_class.report!(root: root)).to be(true)
      end
    end

    it "returns false with a readable schema error" do
      Dir.mktmpdir do |root|
        write_file(root, "docs/claims-manifest.yml", [].to_yaml)
        expect(described_class.report!(root: root)).to be(false)
      end
    end
  end

  describe "command line" do
    it "exits zero when every removed claim is absent" do
      git_repo("README.adoc" => "clean\n") do |root|
        install_checker(root)
        write_manifest(root, [removed_row])
        expect(command_status(root)).to be_success
      end
    end

    it "exits nonzero when a removed claim survives" do
      git_repo("README.adoc" => "16x faster batch processing\n") do |root|
        install_checker(root)
        write_manifest(root, [removed_row])
        expect(command_status(root)).not_to be_success
      end
    end
  end
end
