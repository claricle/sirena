# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "stringio"
require "tmpdir"
require "yaml"
require_relative "../../scripts/apply_case_migration"
require_relative "../../scripts/corpus_case_manifest"

# Builds a small git repository shaped like the real one: two types that
# share a case name (state, state_diagram), verdict and scoreboard files
# sorted by case, fixtures named by the same basename (one under correct/),
# and a spec and a doc quoting cases.
module ApplyCaseMigrationRepo
  PAIRS = [
    ["pie/001_a_0.mmd", "pie/zeta-11111111"],
    ["pie/002_b_1.mmd", "pie/beta-22222222"],
    ["state/003_dup_2.mmd", "state/dup_state-33333333"],
    ["state_diagram/003_dup_2.mmd", "state_diagram/dup_sd-44444444"],
  ].freeze

  SOURCES = {
    "pie/001_a_0" => "pie\n  \"a\": 1\n",
    "pie/002_b_1" => "pie\n  \"b\": 2\n",
    "state/003_dup_2" => "stateDiagram\n  a --> b\n",
    "state_diagram/003_dup_2" => "stateDiagram-v2\n  c --> d\n",
  }.freeze

  def git(*args)
    out, status = Open3.capture2e(
      { "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@example.com",
        "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => "t@example.com" },
      "git", *args, chdir: root
    )
    raise "git #{args.join(' ')} failed: #{out}" unless status.success?

    out
  end

  def put(relative, text)
    full = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, text)
  end

  def build_repo(manifest_pairs: PAIRS, extra_files: {})
    git("init", "-q")
    write_manifest(manifest_pairs)
    SOURCES.each do |id, source|
      put("spec/mermaid/#{id}.mmd", source)
      put("spec/mermaid/#{id}.meta.json", "{}\n")
    end
    write_data_files
    extra_files.each { |relative, text| put(relative, text) }
    git("add", "-A")
    git("commit", "-q", "-m", "seed")
  end

  def write_manifest(pairs)
    entries = pairs.map { |old, new| { "old" => old, "new" => new } }
    put("config/corpus_case_migration.json",
        "#{JSON.pretty_generate('version' => 1, 'pairs' => entries)}\n")
  end

  def write_data_files
    put("spec/mermaid/pie/001_a_0.svg", "<svg/>\n")
    put("spec/fixtures_mermaid/pie/001_a_0.svg", "<svg id='ref'/>\n")
    put("spec/fixtures_mermaid/pie/correct/001_a_0.svg", "<svg id='ref'/>\n")
    put("spec/fixtures_mermaid/state/003_dup_2.svg", "<svg id='st'/>\n")
    put("scoreboard/corpus.json", scoreboard_text)
    put("spec/mermaid/corpus-verdicts.yml", verdicts_text)
    put("spec/pie_spec.rb", spec_text)
    put("notes.md", "Quote: state_diagram/003_dup_2 and pie/002_b_1.mmd.\n")
  end

  def scoreboard_text
    rows = PAIRS.map { |old, _| { "case" => old, "pass" => true } }
    "#{JSON.pretty_generate(rows.sort_by { |row| row['case'] })}\n"
  end

  def verdicts_text
    rows = PAIRS.map { |old, _| { "case" => old, "verdict" => "valid" } }
    YAML.dump(rows.sort_by { |row| row["case"] })
  end

  def spec_text
    <<~RUBY
      File.read("spec/mermaid/pie/001_a_0.mmd")
      name = "002_b_1"
    RUBY
  end

  def snapshot
    Dir.glob("**/*", File::FNM_DOTMATCH, base: root).sort.filter_map do |rel|
      next if rel.start_with?(".git/") || rel == ".git"

      full = File.join(root, rel)
      [rel, File.file?(full) ? File.read(full) : :dir]
    end
  end

  def new_ids = PAIRS.map(&:last)

  def read(relative) = File.read(File.join(root, relative))

  def exist?(relative) = File.exist?(File.join(root, relative))

  def apply_quietly
    ApplyCaseMigration.apply!(root: root)
  rescue ApplyCaseMigration::Error
    nil
  end

  def commit_all(message)
    git("add", "-A")
    git("commit", "-q", "-m", message)
  end

  def run_cli(*argv)
    out = StringIO.new
    err = StringIO.new
    status = ApplyCaseMigration.run(argv, root: root, out: out, err: err)
    [status, out.string, err.string]
  end
end

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

# Two directories for one diagram type: git/ and class/ merge into gitgraph/
# and class_diagram/, whose fixtures are keyed by the same basenames.
module ApplyCaseMigrationMergeRepo
  CASES = {
    "git/002_dup_1" => "gitGraph\n  commit\n",
    "gitgraph/003_dup_2" => "gitGraph\n  commit\n",
    "class/001_c_0" => "classDiagram\n  A --> B\n",
    "class_diagram/002_c_1" => "classDiagram\n  C --> D\n",
  }.freeze

  def build_merge_repo(extra_files: {})
    git("init", "-q")
    write_merge_manifest
    CASES.each do |id, source|
      put("spec/mermaid/#{id}.mmd", source)
      put("spec/mermaid/#{id}.meta.json", meta_for(id))
    end
    merge_data_files.merge(extra_files).each { |file, text| put(file, text) }
    commit_all("seed")
  end

  def write_merge_manifest
    pairs = Dir.mktmpdir("merge-corpus") do |dir|
      write_merge_corpus(dir)
      CorpusCaseManifest.build(corpus_dir: dir)["pairs"]
    end
    put("config/corpus_case_migration.json",
        "#{JSON.pretty_generate('version' => 1, 'pairs' => pairs)}\n")
  end

  def write_merge_corpus(dir)
    CASES.each do |id, source|
      FileUtils.mkdir_p(File.join(dir, File.dirname(id)))
      File.write(File.join(dir, "#{id}.mmd"), source)
      File.write(File.join(dir, "#{id}.meta.json"), meta_for(id))
    end
  end

  def meta_for(id)
    "#{JSON.pretty_generate('name' => 'x', 'type' => File.dirname(id),
                            'source_file' => '/cypress/platform/x.html')}\n"
  end

  def merge_data_files
    { "spec/fixtures_mermaid/class/001_c_0.svg" => "<svg id='c'/>\n",
      "spec/fixtures_mermaid/class/correct/001_c_0.svg" => "<svg id='cc'/>\n",
      "spec/fixtures_mermaid/gitgraph/002_dup_1.svg" => "<svg id='g1'/>\n",
      "spec/fixtures_mermaid/gitgraph/003_dup_2.svg" => "<svg id='g2'/>\n",
      "notes.md" => "see spec/mermaid/class/001_c_0.mmd and " \
                    "spec/fixtures_mermaid/class/correct/001_c_0.svg\n",
      "spec/dir_spec.rb" => "File.expand_path(\"../mermaid/git\", __dir__)\n",
      "scoreboard/corpus.json" => "#{JSON.pretty_generate(scoreboard_rows)}\n" }
  end

  def scoreboard_rows
    CASES.keys.sort.map { |id| { "case" => "#{id}.mmd", "pass" => true } }
  end

  def ids_of(old)
    JSON.parse(read("config/corpus_case_migration.json"))["pairs"]
      .to_h { [_1["old"], _1["new"]] }.fetch("#{old}.mmd")
  end
end

RSpec.describe ApplyCaseMigration, "merging duplicate directories" do
  include ApplyCaseMigrationRepo
  include ApplyCaseMigrationMergeRepo

  let(:root) { Dir.mktmpdir("apply-case-merge") }

  before { build_merge_repo }

  after { FileUtils.remove_entry(root) }

  def moved(old)
    "spec/mermaid/#{ids_of(old.delete_suffix('.mmd'))}.mmd"
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

  context "after apply" do
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
      meta = JSON.parse(read(moved("class/001_c_0.mmd").sub(/mmd\z/, "meta.json")))
      expect(meta["type"]).to eq("class_diagram")
    end

    it "leaves the type of a case that did not move" do
      meta = JSON.parse(read(moved("class_diagram/002_c_1.mmd")
                               .sub(/mmd\z/, "meta.json")))
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
    it "reports a case left in a merged-away directory" do
      described_class.apply!(root: root)
      put("spec/mermaid/class/straggler.txt", "x\n")
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

    it "refuses with a conflict and writes nothing" do
      seeded = snapshot
      expect { described_class.apply!(root: root) }
        .to raise_error(ApplyCaseMigration::ConflictError)
      expect(snapshot).to eq(seeded)
    end
  end

  describe "a manifest that sends one directory two ways" do
    it "is refused" do
      pairs = [["class/001_c_0.mmd", "class_diagram/x-11111111"],
               ["class/002_c_1.mmd", "er_diagram/y-22222222"]]
      write_manifest(pairs)
      commit_all("split")
      expect { described_class.plan(root: root) }
        .to raise_error(ApplyCaseMigration::ConflictError, /two ways/)
    end
  end
end
