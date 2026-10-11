# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "yaml"
require_relative "../../scripts/apply_case_migration"
require_relative "apply_case_migration_repo"

RSpec.describe ApplyCaseMigration do
  include ApplyCaseMigrationRepo
  include ApplyCaseMigrationMergeRepo

  let(:root) { Dir.mktmpdir("apply-case-merge") }

  before { build_merge_repo }

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

  def moved(old)
    "spec/mermaid/#{ids_of(old.delete_suffix('.mmd'))}.mmd"
  end

  def meta_path(old)
    "spec/mermaid/#{ids_of(old)}.meta.json"
  end

  describe ".plan" do
    subject(:plan) { described_class.plan(root: root) }

    it "finds no conflict between the twins that share a directory" do
      expect([plan.unresolved, plan.conflicts]).to eq([[], []])
    end

    it "writes nothing" do
      seeded = snapshot
      plan
      expect(snapshot).to eq(seeded)
    end
  end

  context "when applied" do
    before { described_class.apply!(root: root) }

    it "moves a case into the canonical directory" do
      expect(exist?(moved("git/002_dup_1.mmd"))).to be(true)
    end

    it "keeps both twins, under different names" do
      names = %w[git/002_dup_1 gitgraph/003_dup_2].map { ids_of(_1) }
      expect(names.uniq.length).to eq(2)
    end

    it "moves a sidecar with its case" do
      new = ids_of("class/001_c_0")
      expect(exist?("spec/mermaid/#{new}.meta.json")).to be(true)
    end

    it "removes the merged-away directories" do
      expect([exist?("spec/mermaid/git"), exist?("spec/mermaid/class"),
              exist?("spec/fixtures_mermaid/class")]).to eq([false] * 3)
    end

    it "moves a fixture into the canonical fixture directory" do
      new = ids_of("class/001_c_0").split("/").last
      expect(exist?("spec/fixtures_mermaid/class_diagram/#{new}.svg"))
        .to be(true)
    end

    it "moves a fixture under correct/ the same way" do
      new = ids_of("class/001_c_0").split("/").last
      expect(exist?("spec/fixtures_mermaid/class_diagram/correct/#{new}.svg"))
        .to be(true)
    end

    it "keeps two fixtures of one directory apart" do
      expect(Dir.children(File.join(root, "spec/fixtures_mermaid/gitgraph"))
               .length).to eq(2)
    end

    it "rewrites the directory of a quoted path with the name" do
      new = ids_of("class/001_c_0").split("/").last
      expect(read("notes.md")).to eq(
        "see spec/mermaid/class_diagram/#{new}.mmd and " \
        "spec/fixtures_mermaid/class_diagram/correct/#{new}.svg\n",
      )
    end

    it "rewrites a bare directory path in code" do
      expect(read("spec/dir_spec.rb"))
        .to eq("File.expand_path(\"../mermaid/gitgraph\", __dir__)\n")
    end

    it "rewrites the type a merged case's meta names" do
      meta = JSON.parse(read(meta_path("class/001_c_0")))
      expect(meta["type"]).to eq("class_diagram")
    end

    it "leaves the type of a case that did not move" do
      meta = JSON.parse(read(meta_path("class_diagram/002_c_1")))
      expect(meta["type"]).to eq("class_diagram")
    end

    it "rewrites case keys in the scoreboard to the canonical directory" do
      cases = JSON.parse(read("scoreboard/corpus.json")).map { _1["case"] }
      expect(cases.map { _1.split("/").first }.uniq)
        .to eq(%w[class_diagram gitgraph])
    end

    it "verifies clean" do
      expect(described_class.verify(root: root)).to eq([])
    end
  end

  describe "verify before the merge" do
    before do
      described_class.apply!(root: root)
      put("spec/mermaid/class/straggler.txt", "x\n")
    end

    it "reports a case left in a merged-away directory" do
      expect(described_class.verify(root: root)).to include(
        "spec/mermaid/class/straggler.txt: still in a directory that was " \
        "merged away",
      )
    end
  end

  context "when a stray file sits in a directory being merged away" do
    before do
      put("spec/mermaid/git/README.txt", "stray\n")
      commit_all("stray")
    end

    it "lists it as unresolved" do
      expect(described_class.plan(root: root).unresolved).to include(
        a_string_starting_with("spec/mermaid/git/README.txt"),
      )
    end

    it "writes nothing" do
      seeded = snapshot
      apply_quietly
      expect(snapshot).to eq(seeded)
    end
  end

  context "when a merged case lands on a name that is taken" do
    before do
      new = ids_of("class/001_c_0")
      put("spec/mermaid/#{new}.mmd", "taken\n")
      commit_all("squatter")
    end

    it_behaves_like "a refusal that writes nothing",
                    ApplyCaseMigration::ConflictError
  end

  describe "a manifest that sends one directory two ways" do
    before do
      write_manifest([["class/001_c_0.mmd", "class_diagram/x-11111111"],
                      ["class/002_c_1.mmd", "er_diagram/y-22222222"]])
      commit_all("split")
    end

    it "is refused" do
      expect { described_class.plan(root: root) }
        .to raise_error(ApplyCaseMigration::ConflictError, /two ways/)
    end
  end
end
