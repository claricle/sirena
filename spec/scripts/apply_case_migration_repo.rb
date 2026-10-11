# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"
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
