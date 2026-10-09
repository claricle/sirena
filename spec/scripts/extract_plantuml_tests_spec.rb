# frozen_string_literal: true

require "json"
require_relative "../../scripts/extract_plantuml_tests"

RSpec.describe PlantumlExtractor do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:corpus) { File.join(root, "spec/plantuml") }

  let(:diagram_a) { "@startuml\nclass Foo\nFoo --> Bar\n@enduml" }
  let(:diagram_b) { "@startuml\nparticipant A\nA -> B : hi\n@enduml" }

  def block(text, path: "src/test/resources/a/b.puml")
    described_class::Blocks.from_resource(path, text, test: File.basename(path, ".puml"))
  end

  def ids_for(blocks)
    described_class::Cases.build(blocks).keys
  end

  describe "case IDs" do
    it "keeps every existing ID when a fixture is inserted upstream before, after and beside it" do
      before = ids_for(block("#{diagram_a}\n#{diagram_b}\n"))
      inserted = "@startuml\nclass New\n@enduml\n"
      sibling = block(inserted, path: "src/test/resources/a/aaa.puml")
      after = ids_for(block("#{inserted}\n#{diagram_a}\n#{diagram_b}\n#{inserted.sub('New', 'Tail')}") + sibling)

      expect(after).to include(*before)
      expect(after.size).to eq(before.size + 3)
    end

    it "does not change when only line endings or trailing whitespace change" do
      plain = ids_for(block(diagram_a))
      noisy = ids_for(block("#{diagram_a.gsub("\n", " \r\n")}\n\n"))

      expect(noisy).to eq(plain)
    end

    it "changes when the diagram text changes" do
      expect(ids_for(block(diagram_a.sub("Bar", "Baz")))).not_to eq(ids_for(block(diagram_a)))
    end

    it "contains no ordinal and no machine path" do
      id = ids_for(block(diagram_a, path: "src/test/resources/vega/x/y.puml")).first

      expect(id).to match(/\Aresources\.vega\.x\.y--\h{12}\z/)
    end

    it "collapses identical blocks from one file into one counted case" do
      cases = described_class::Cases.build(block("#{diagram_a}\n#{diagram_a}\n"))

      expect(cases.size).to eq(1)
      expect(cases.values.first[:meta][:occurrences]).to eq(2)
    end
  end

  describe "selection" do
    {
      "explicit class" => ["@startuml\nclass A\n@enduml", "class"],
      "interface" => ["@startuml\ninterface I\n@enduml", "class"],
      "participant" => ["@startuml\nparticipant A\n@enduml", "sequence"],
      "divider" => ["@startuml\nA -> B\n== x ==\n@enduml", "sequence"],
      "bare message" => ["@startuml\nA -> B : hi\n@enduml", nil],
      "class and sequence mixed" => ["@startuml\nclass A\nparticipant B\n@enduml", nil],
      "state diagram" => ["@startuml\nstate S\nclass A\n@enduml", nil],
      "usecase" => ["@startuml\nactor U\nusecase X\nparticipant P\n@enduml", nil],
    }.each do |label, (source, type)|
      it "classifies #{label} as #{type.inspect}" do
        expect(described_class::Selection.type_of(source)).to eq(type)
      end
    end

    it "drops .puml front matter and non-uml blocks" do
      blocks = block("---\nexpected: x\n---\n#{diagram_a}\n@startgantt\n[T] lasts 1 day\n@endgantt\n")

      expect(blocks.map(&:source)).to eq([diagram_a])
    end

    it "reads Java text blocks verbatim and records the origin" do
      java = "/*\n\"\"\"\n#{diagram_b}\n\"\"\"\n*/\nclass T {}\n"
      found = described_class::Blocks.from_java("src/test/java/n/T.java", java, test: "T")

      expect(found.map(&:origin)).to eq(["java-text-block"])
      expect(found.first.source).to eq(diagram_b)
    end
  end

  describe "the committed corpus" do
    let(:pin) { JSON.parse(File.read(File.join(corpus, "pin.json"))) }

    it "matches the checksum and counts recorded in pin.json" do
      expect(described_class::Manifest.digest(corpus)).to eq(pin.dig("corpus", "manifest_sha256"))
      expect(described_class::Manifest.counts(corpus)).to eq(pin.dig("corpus", "cases"))
    end

    it "has meta whose source hash matches the .puml beside it" do
      Dir.glob(File.join(corpus, "*/*.meta.json")).each do |path|
        meta = JSON.parse(File.read(path))
        source = File.read(path.sub(/\.meta\.json\z/, ".puml"))

        expect(described_class::CaseId.source_hash(source)).to eq(meta["source_sha256"])
        expect(File.basename(path, ".meta.json")).to eq(meta["id"])
      end
    end

    it "pins a full upstream SHA" do
      expect(pin.dig("upstream", "sha")).to match(/\A\h{40}\z/)
    end

    it "states the cohort is upstream fixtures, not real-world files" do
      expect(File.read(File.join(corpus, "README.md"))).to include("NOT real-world files")
    end

    it "has scoreboard rows for class and sequence at 0 passing and the right case count" do
      rows = JSON.parse(File.read(File.join(root, "scoreboard/plantuml.json")))

      expect(rows.to_h { |r| [r["type"], [r["cases"], r["passing"]]] })
        .to eq("class" => [pin.dig("corpus", "cases", "class"), 0],
               "sequence" => [pin.dig("corpus", "cases", "sequence"), 0])
    end
  end
end
