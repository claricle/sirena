# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"
require "tmpdir"
require "yaml"
require_relative "../../scripts/apply_case_migration"
require_relative "apply_case_migration_repo"

RSpec.describe ApplyCaseMigration do
  include ApplyCaseMigrationRepo

  let(:root) { Dir.mktmpdir("apply-case-migration") }
  let(:repo) { ApplyCaseMigrationRepo }

  before { build_repo }

  after { FileUtils.remove_entry(root) }

  shared_examples "a refusal that writes nothing" do |error|
    it "raises #{error}" do
      expect { described_class.apply!(root: root) }.to raise_error(error)
    end

    it "leaves every file as it was" do
      seeded = snapshot
      apply_quietly
      expect(snapshot).to eq(seeded)
    end
  end

  describe ".plan" do
    subject(:plan) { described_class.plan(root: root) }

    it "writes nothing" do
      seeded = snapshot
      plan
      expect(snapshot).to eq(seeded)
    end

    it "leaves git status clean" do
      plan
      expect(git("status", "--porcelain")).to eq("")
    end

    it "lists a move for every case file and fixture" do
      expect(plan.moves.length).to eq(12)
    end

    it "finds nothing unresolved or in conflict" do
      expect([plan.unresolved, plan.conflicts]).to eq([[], []])
    end
  end

  describe "--dry-run" do
    it "prints the moves" do
      expect(run_cli("--dry-run")[1]).to include(
        "move spec/mermaid/pie/001_a_0.mmd -> " \
        "spec/mermaid/pie/zeta-11111111.mmd",
      )
    end

    it "writes nothing" do
      seeded = snapshot
      run_cli("--dry-run")
      expect(snapshot).to eq(seeded)
    end

    it "fails while something blocks the apply" do
      put("loose.md", "see 003_dup_2\n")
      commit_all("loose")
      expect(run_cli("--dry-run").first).to eq(1)
    end
  end

  describe ".apply!" do
    before { described_class.apply!(root: root) }

    %w[spec/mermaid/pie/zeta-11111111.mmd
       spec/mermaid/pie/zeta-11111111.meta.json
       spec/mermaid/pie/zeta-11111111.svg
       spec/fixtures_mermaid/pie/zeta-11111111.svg
       spec/fixtures_mermaid/pie/correct/zeta-11111111.svg
       spec/fixtures_mermaid/state/dup_state-33333333.svg].each do |file|
      it "creates #{file}" do
        expect(exist?(file)).to be(true)
      end
    end

    it "removes the old case file" do
      expect(exist?("spec/mermaid/pie/001_a_0.mmd")).to be(false)
    end

    it "removes the old fixture copy under correct/" do
      expect(exist?("spec/fixtures_mermaid/pie/correct/001_a_0.svg"))
        .to be(false)
    end

    it "rewrites a shared name by the directory beside it" do
      expect(read("notes.md")).to eq(
        "Quote: state_diagram/dup_sd-44444444 and pie/beta-22222222.mmd.\n",
      )
    end

    it "rewrites paths and bare names in specs" do
      expect(read("spec/pie_spec.rb")).to eq(<<~RUBY)
        File.read("spec/mermaid/pie/zeta-11111111.mmd")
        name = "beta-22222222"
      RUBY
    end

    it "re-sorts a JSON scoreboard by the new names" do
      cases = JSON.parse(read("scoreboard/corpus.json")).map { _1["case"] }
      expect(cases.first).to eq("pie/beta-22222222.mmd")
    end

    it "re-sorts a YAML verdict list by the new names" do
      cases = YAML.safe_load(read("spec/mermaid/corpus-verdicts.yml"))
        .map { _1["case"] }
      expect(cases).to eq(cases.sort)
    end

    it "leaves the manifest as it was" do
      expect(read("config/corpus_case_migration.json"))
        .to include("pie/001_a_0.mmd")
    end

    it "keeps the case count" do
      ids = Dir.glob("*/*.mmd", base: File.join(root, "spec/mermaid"))
      expect(ids.length).to eq(repo::PAIRS.length)
    end

    it "verifies clean" do
      expect(described_class.verify(root: root)).to eq([])
    end
  end

  describe "a target that already exists" do
    before do
      put("spec/mermaid/pie/zeta-11111111.mmd", "taken\n")
      commit_all("squatter")
    end

    it_behaves_like "a refusal that writes nothing",
                    ApplyCaseMigration::ConflictError
  end

  describe "two old cases mapping to one new one" do
    before do
      pairs = repo::PAIRS.dup
      pairs[1] = [pairs[1].first, pairs[0].last]
      write_manifest(pairs)
      commit_all("bad manifest")
    end

    it_behaves_like "a refusal that writes nothing",
                    ApplyCaseMigration::ConflictError

    it "names the manifest" do
      expect { described_class.plan(root: root) }
        .to raise_error(ApplyCaseMigration::ConflictError, /new_base twice/)
    end
  end

  describe "an old case listed twice" do
    before do
      write_manifest(repo::PAIRS + [["pie/001_a_0.mmd", "pie/other-55555555"]])
      commit_all("old twice")
    end

    it_behaves_like "a refusal that writes nothing",
                    ApplyCaseMigration::ConflictError

    it "names the manifest" do
      expect { described_class.plan(root: root) }
        .to raise_error(ApplyCaseMigration::ConflictError, /old_base twice/)
    end
  end

  describe "two files renamed onto one target" do
    before do
      clash = ["state/004_other_3.mmd", "state/dup_state-33333333"]
      pairs = repo::PAIRS + [clash]
      write_manifest(pairs)
      put("spec/mermaid/state/004_other_3.mmd", "stateDiagram\n")
      put("spec/mermaid/state/004_other_3.meta.json", "{}\n")
      put("spec/fixtures_mermaid/state/004_other_3.svg", "<svg/>\n")
      commit_all("clash")
    end

    it_behaves_like "a refusal that writes nothing",
                    ApplyCaseMigration::ConflictError
  end

  describe "a dirty tree" do
    before { put("scratch.txt", "uncommitted\n") }

    it_behaves_like "a refusal that writes nothing",
                    ApplyCaseMigration::DirtyTreeError
  end

  describe "a shared name with no directory and no twin" do
    before do
      put("loose.md", "see 003_dup_2 for details\n")
      commit_all("loose")
    end

    it_behaves_like "a refusal that writes nothing",
                    ApplyCaseMigration::UnresolvedError
  end

  describe "a shared name beside an entry with a byte-identical twin" do
    before do
      twin_source = repo::SOURCES.fetch("state/003_dup_2")
      put("spec/mermaid/pie/001_a_0.mmd", twin_source)
      put("spec/mermaid/corpus-verdicts.yml", <<~YAML)
        - case: pie/001_a_0.mmd
          evidence: 'twin rendered: 003_dup_2'
      YAML
      commit_all("twin")
      described_class.apply!(root: root)
    end

    it "resolves the name to the candidate with the same source" do
      expect(read("spec/mermaid/corpus-verdicts.yml"))
        .to include("twin rendered: dup_state-33333333")
    end
  end

  describe ".verify" do
    it "names the old files before the migration" do
      expect(described_class.verify(root: root))
        .to include(a_string_matching(/001_a_0.*file still has an old name/))
    end

    it "fails when an old reference is left behind" do
      described_class.apply!(root: root)
      put("late.md", "still says 001_a_0\n")
      expect(described_class.verify(root: root))
        .to eq(["late.md: old name 001_a_0 still referenced"])
    end

    it "fails when a new case file is missing" do
      described_class.apply!(root: root)
      File.delete(File.join(root, "spec/mermaid/pie/beta-22222222.meta.json"))
      expect(described_class.verify(root: root))
        .to eq(["spec/mermaid/pie/beta-22222222.meta.json: missing"])
    end

    it "fails when the case count changed" do
      described_class.apply!(root: root)
      put("spec/mermaid/pie/extra-99999999.mmd", "pie\n")
      expect(described_class.verify(root: root))
        .to include(a_string_matching(/holds 5 cases, the manifest names 4/))
    end
  end

  describe ".run" do
    it "needs a mode" do
      expect(run_cli.first).to eq(2)
    end

    it "applies and verifies" do
      expect(run_cli("--apply").first).to eq(0)
    end

    it "verifies a finished migration" do
      run_cli("--apply")
      expect(run_cli("--verify")[1]).to eq("verify: ok\n")
    end

    it "reports a refusal as a failing status" do
      put("scratch.txt", "x\n")
      expect(run_cli("--apply").values_at(0, 2))
        .to match([1, /DirtyTreeError/])
    end
  end
end
