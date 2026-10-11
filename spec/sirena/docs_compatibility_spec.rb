# frozen_string_literal: true

require "spec_helper"
require "rake"
require "json"
require "tmpdir"

load File.expand_path("../../tasks/compatibility.rake", __dir__)

RSpec.describe Sirena::DocsCompatibility do
  let(:board) { described_class }
  let(:corpus_root) { File.expand_path("../mermaid", __dir__) }
  let(:scoreboard_path) do
    path = File.join(Dir.mktmpdir, "scoreboard.json")
    File.write(path, JSON.generate(scoreboard_rows))
    path
  end
  let(:rows) do
    [
      { case: "class/1.mmd", verdict: "valid", pass: true },
      { case: "class_diagram/2.mmd", verdict: "valid", pass: false },
      { case: "class/3.mmd", verdict: "artifact", pass: false },
      { case: "pie/4.mmd", verdict: "invalid", pass: true },
    ]
  end

  it "keeps the page's generated region equal to the scoreboard's" do
    expect(File.read(board::PAGE_PATH)).to include(board.region)
  end

  it "keeps every per-type claim equal to the scoreboard's generated region" do
    board::TYPE_PAGES.each_key do |label|
      path = board.type_page_path(label)

      expect(File.read(path)).to include(board.type_page_region(label))
    end
  end

  context "with non-valid corpus verdicts" do
    subject(:type_page_region) do
      board.type_page_region("Pie Chart", scoreboard_path)
    end

    let(:scoreboard_rows) do
      [
        { case: "pie/1.mmd", verdict: "valid", pass: true },
        { case: "pie/2.mmd", verdict: "valid", pass: false },
        { case: "pie/3.mmd", verdict: "invalid", pass: true },
      ]
    end

    it "reports them outside the compatibility denominator" do
      expect(type_page_region).to include("1/2 passing (50.0%)")
        .and include("1/1 `invalid` cases currently render")
    end
  end

  it "keeps the PlantUML claim equal to its scoreboard's generated region" do
    expect(File.read(board::PLANTUML_PAGE_PATH))
      .to include(board.plantuml_region)
  end

  context "with measured PlantUML rows" do
    let(:scoreboard_rows) do
      [
        { type: "class", oracle_valid: 4, passing: 3 },
        { type: "sequence", oracle_valid: 7, passing: 5 },
      ]
    end

    it "generates PlantUML pass counts" do
      expect(board.plantuml_region(scoreboard_path))
        .to include("class 3/4, sequence 5/7 oracle-valid cases")
    end
  end

  it "counts only oracle-valid cases, summing a type's directories" do
    path = File.join(Dir.mktmpdir, "corpus.json")
    File.write(path, JSON.generate(rows))

    expect(board.counts(path)).to include("Class Diagram" => [1, 2],
                                          "Pie Chart" => [0, 0])
  end

  it "covers every corpus directory except the untyped 'unknown' one" do
    dirs = Dir.children(corpus_root).select do |name|
      File.directory?(File.join(corpus_root, name))
    end

    expect(dirs - board::TYPES.flat_map(&:last)).to eq(["unknown"])
  end
end
