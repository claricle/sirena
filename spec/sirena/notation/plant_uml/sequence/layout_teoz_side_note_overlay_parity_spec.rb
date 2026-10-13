# frozen_string_literal: true

require "nokogiri"
require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  let(:source_path) do
    File.expand_path("../../../../plantuml/sequence/" \
                     "resources.vega.nonreg.group2834." \
                     "nested_groups_and_notes--846af1d12917.puml", __dir__)
  end
  let(:source) { File.read(source_path) }

  context "with side notes" do
    let(:without_note) { source.sub(/note right of Bob\n.*?end note\n/m, "") }
    let(:scenes) do
      inputs = [source, source.sub("note right", "note left"), without_note]
      inputs.map do |input|
        parsed = Sirena::Notation::PlantUML::Sequence.parse(input)
        parsed.transform.new.call(parsed.diagram)
      end
    end
    let(:gauges) do
      scenes.map do |scene|
        origin = scene.lifelines.first.x1
        scene.lifelines.map { |line| (line.x1 - origin).round(4) }
      end
    end

    it "keeps the nested_groups_and_notes gauge independent of side notes" do
      expect(gauges.first(2)).to all(eq(gauges.last))
    end
  end

  context "with the pinned reference" do
    let(:reference) do
      path = source_path.sub("/sequence/", "/references/sequence/")
        .sub(/\.puml\z/, ".svg")
      Nokogiri::XML(File.read(path)).remove_namespaces!
    end
    let(:scene) do
      parsed = Sirena::Notation::PlantUML::Sequence.parse(source)
      parsed.transform.new.call(parsed.diagram)
    end
    let(:crossings) do
      carol = reference.at_xpath('//g[title="Carol"]/rect')["x"].to_f + 4
      note = reference.at_xpath('//text[text()="a note wide enough to"]')
      reference_right = note["x"].to_f + note["textLength"].to_f
      coordinates = scene.notes.first.path.scan(/-?\d+(?:\.\d+)?/)
      [reference_right > carol, coordinates[4].to_f > scene.lifelines.last.x1]
    end

    it "allows the note to cross Carol's lifeline as the reference does" do
      expect(crossings).to eq([true, true])
    end
  end
end
