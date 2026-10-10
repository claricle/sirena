# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"
Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  let(:source) do
    [
      "@startuml",
      "class Box<T> <<entity>> {",
      "  {static}{abstract} +compute() : int",
      "}",
      "class Child",
      "Box +-- Child",
      "note right of Box #red : memo",
      "@enduml",
      "",
    ].join("\n")
  end
  let(:layout) { described_class.new }
  let(:scene) do
    parsed = Sirena::Notation::PlantUML.parse(source)
    layout.call(parsed.diagram)
  end
  let(:boxes) { scene.boxes.to_h { |box| [box.id, box] } }
  let(:expected_rows) do
    [
      ["<<entity>>", "kind"],
      ["Box<T>", "class_name"],
      ["+compute() : int", "member_abstract"],
    ]
  end

  it "lays out tagged generic classes and modified members" do
    box = boxes.fetch("Box")
    rows = box.texts.map { |text| [text.content, text.role] }

    expect([rows, box.separators.size]).to eq([expected_rows, 2])
  end

  it "lays out a coloured note as note content" do
    note = boxes.fetch("note-0")

    expect([note.kind, note.fill, note.texts.map(&:content)])
      .to eq(["note", "#red", ["memo"]])
  end

  it "lays out the nesting end as a nesting marker" do
    marker = scene.relations.fetch(0).markers.fetch(0)

    expect(marker.shape).to eq("nesting")
  end

  it "uses a horizontal direction for coincident points" do
    expect(layout.send(:unit_vector, [4.0, 2.0], [4.0, 2.0]))
      .to eq([1.0, 0.0])
  end
end
