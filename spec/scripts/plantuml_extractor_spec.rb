# frozen_string_literal: true

require "json"
require "yaml"
require_relative "../../scripts/extract_plantuml_tests"

module PlantumlExtractorSpecSupport
  def diagram_a = "@startuml\nclass Foo\nFoo --> Bar\n@enduml"
  def diagram_b = "@startuml\nparticipant A\nA -> B : hi\n@enduml"

  def block(text, path: "src/test/resources/a/b.puml")
    test = File.basename(path, ".puml")
    PlantumlExtractor::Blocks.from_resource(path, text, test: test)
  end

  def ids_for(blocks)
    PlantumlExtractor::Cases.build(blocks).keys
  end

  # [source hashes recomputed from each .puml, hashes the .meta.json records]
  # plus the same for ids, paired up per case.
  def corpus_hashes_and_ids(corpus)
    pairs = Dir.glob(File.join(corpus, "*/*.meta.json")).map do |path|
      meta = JSON.parse(File.read(path))
      source = File.read(path.sub(/\.meta\.json\z/, ".puml"))
      [[PlantumlExtractor::CaseId.source_hash(source),
        File.basename(path, ".meta.json")],
       [meta["source_sha256"], meta["id"]]]
    end
    pairs.transpose
  end
end

RSpec.describe PlantumlExtractor do
  include PlantumlExtractorSpecSupport

  let(:root) { File.expand_path("../..", __dir__) }
  let(:corpus) { File.join(root, "spec/plantuml") }

  describe "case IDs" do
    let(:before_ids) { ids_for(block("#{diagram_a}\n#{diagram_b}\n")) }
    let(:after_ids) do
      inserted = "@startuml\nclass New\n@enduml\n"
      sibling = block(inserted, path: "src/test/resources/a/aaa.puml")
      tail = inserted.sub("New", "Tail")
      text = "#{inserted}\n#{diagram_a}\n#{diagram_b}\n#{tail}"
      ids_for(block(text) + sibling)
    end

    it "keeps every existing ID when a fixture is inserted around it" do
      expect(after_ids).to include(*before_ids)
    end

    it "adds one ID per fixture inserted before, after and beside it" do
      expect(after_ids.size).to eq(before_ids.size + 3)
    end

    it "does not change when only line endings or trailing whitespace change" do
      plain = ids_for(block(diagram_a))
      noisy = ids_for(block("#{diagram_a.gsub("\n", " \r\n")}\n\n"))

      expect(noisy).to eq(plain)
    end

    it "changes when the diagram text changes" do
      changed = ids_for(block(diagram_a.sub("Bar", "Baz")))

      expect(changed).not_to eq(ids_for(block(diagram_a)))
    end

    it "contains no ordinal and no machine path" do
      path = "src/test/resources/vega/x/y.puml"
      id = ids_for(block(diagram_a, path: path)).first

      expect(id).to match(/\Aresources\.vega\.x\.y--\h{12}\z/)
    end

    context "with identical blocks from one file" do
      let(:cases) do
        described_class::Cases.build(block("#{diagram_a}\n#{diagram_a}\n"))
      end

      it "collapses them into one case" do
        expect(cases.size).to eq(1)
      end

      it "counts the occurrences" do
        expect(cases.values.first[:meta][:occurrences]).to eq(2)
      end
    end
  end

  describe "selection" do
    {
      "explicit class" => ["@startuml\nclass A\n@enduml", "class"],
      "interface" => ["@startuml\ninterface I\n@enduml", "class"],
      "participant" => ["@startuml\nparticipant A\n@enduml", "sequence"],
      "divider" => ["@startuml\nA -> B\n== x ==\n@enduml", "sequence"],
      "bare message" => ["@startuml\nA -> B : hi\n@enduml", nil],
      "class and sequence mixed" =>
        ["@startuml\nclass A\nparticipant B\n@enduml", nil],
      "state diagram" => ["@startuml\nstate S\nclass A\n@enduml", nil],
      "usecase" =>
        ["@startuml\nactor U\nusecase X\nparticipant P\n@enduml", nil],
    }.each do |label, (source, type)|
      it "classifies #{label} as #{type.inspect}" do
        expect(described_class::Selection.type_of(source)).to eq(type)
      end
    end

    it "drops .puml front matter and non-uml blocks" do
      gantt = "@startgantt\n[T] lasts 1 day\n@endgantt\n"
      blocks = block("---\nexpected: x\n---\n#{diagram_a}\n#{gantt}")

      expect(blocks.map(&:source)).to eq([diagram_a])
    end

    context "with a Java text block" do
      let(:found) do
        java = "/*\n\"\"\"\n#{diagram_b}\n\"\"\"\n*/\nclass T {}\n"
        described_class::Blocks.from_java("src/test/java/n/T.java", java,
                                          test: "T")
      end

      it "records the origin" do
        expect(found.map(&:origin)).to eq(["java-text-block"])
      end

      it "reads the text verbatim" do
        expect(found.first.source).to eq(diagram_b)
      end
    end
  end

  describe "the committed corpus" do
    let(:pin) { JSON.parse(File.read(File.join(corpus, "pin.json"))) }

    it "matches the checksum recorded in pin.json" do
      expect(described_class::Manifest.digest(corpus))
        .to eq(pin.dig("corpus", "manifest_sha256"))
    end

    it "matches the counts recorded in pin.json" do
      expect(described_class::Manifest.counts(corpus))
        .to eq(pin.dig("corpus", "cases"))
    end

    it "has meta whose source hash and id match the .puml beside it" do
      actual, recorded = corpus_hashes_and_ids(corpus)

      expect(actual).to eq(recorded)
    end

    it "pins a full upstream SHA" do
      expect(pin.dig("upstream", "sha")).to match(/\A\h{40}\z/)
    end

    it "states the cohort is upstream fixtures, not real-world files" do
      readme = File.read(File.join(corpus, "README.md"))

      expect(readme).to include("NOT real-world files")
    end

    it "has scoreboard rows with the measured oracle-valid denominators" do
      rows = JSON.parse(File.read(File.join(root, "scoreboard/plantuml.json")))
      counts = pin.dig("corpus", "cases")
      verdicts = YAML.load_file(File.join(corpus, "oracle-verdicts.yml"))
        .fetch("verdicts")
      valid = verdicts.select { |record| record["verdict"] == "valid" }
        .group_by { |record| record.fetch("id").split("/", 2).first }
        .transform_values(&:size)

      actual = rows.to_h do |row|
        [row["type"], [row["cases"], row["oracle_valid"], row["passing"]]]
      end
      expect(actual).to eq("class" => [counts["class"], valid["class"], 0],
                           "sequence" => [counts["sequence"],
                                          valid["sequence"], 0])
    end
  end
end
