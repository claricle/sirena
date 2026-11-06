# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"
Sirena::Notation.send(:entries).delete(:plantuml)

# Geometry below is measured from PlantUML 1.2026.6 (the pinned reference).
RSpec.describe Sirena::Notation::PlantUML::Layout do
  let(:scene) do
    layout = described_class.new
    layout.call(Sirena::Notation::PlantUML.parse(source).diagram)
  end
  let(:box) { scene.boxes.find { |candidate| candidate.id == "Dummy" } }
  let(:rows) { box.texts.reject { |text| text.role == "class_name" } }

  context "with a field and a method, two classes apart" do
    let(:source) do
      "@startuml\nclass Dummy {\n  String data\n  void methods()\n}\n" \
        "class Flight {\n  flightNumber : Integer\n}\n@enduml\n"
    end

    it "is as tall as the 16.49 row pitch makes it" do
      expect(box.height).to be_within(0.001).of(80.9766)
    end

    it "is as wide as its widest proportional row" do
      expect(box.width).to be_within(0.001).of(113.582)
    end

    it "starts plain text 6 in" do
      expect(rows.map(&:x)).to all(eq(box.x + 6.0))
    end

    it "sets the rows 24.49 apart across the group gap" do
      expect(rows.last.y - rows.first.y).to be_within(0.001).of(24.4883)
    end
  end

  context "with visibility markers" do
    let(:source) do
      "@startuml\nclass Dummy {\n  -f1\n  #f2\n  ~f3\n  +f4\n  +m1()\n}\n" \
        "@enduml\n"
    end

    it "gives each member its icon in place of the written prefix" do
      expect(rows.map { |text| [text.content, text.icon&.shape] }).to eq(
        [["f1", "square"], ["f2", "diamond"], ["f3", "triangle"],
         ["f4", "circle"], ["m1()", "circle"]],
      )
    end

    it "starts text 20 in, as PlantUML does" do
      expect(rows.map(&:x)).to all(eq(box.x + 20.0))
    end

    it "is as wide as the indent, the widest row and 6 beyond" do
      widest = Sirena::Notation::PlantUML::Drawing::Face
        .widest_line("m1()", size: 14.0)

      expect(box.width).to be >= 20.0 + widest + 6.0
    end
  end

  context "with `skinparam classAttributeIconSize 0`" do
    let(:source) do
      "@startuml\nskinparam classAttributeIconSize 0\nclass Dummy {\n  " \
        "-f1\n  +m1()\n}\n@enduml\n"
    end

    it "keeps the prefix in the text and draws no icon" do
      expect(rows.map { |text| [text.content, text.icon, text.x - box.x] })
        .to eq([["-f1", nil, 6.0], ["+m1()", nil, 6.0]])
    end
  end

  context "with a bare separator between two fields" do
    let(:source) { "@startuml\nclass Dummy {\n  a\n  ..\n  b\n}\n@enduml\n" }

    it "adds 8 for the separator and no closing method gap" do
      expect(box.height).to be_within(0.001).of(40.0 + 32.9766 + 8.0)
    end
  end

  context "with members hidden and one portion shown" do
    let(:source) do
      "@startuml\nhide members\nshow Dummy methods\nclass Dummy {\n  " \
        "~run()\n}\n@enduml\n"
    end

    it "drops the empty field compartment" do
      expect(box.height).to be_within(0.001).of(56.4883)
    end
  end

  context "with a stereotype row above the members" do
    let(:source) do
      "@startuml\nclass Dummy <<entity>> {\n  +run()\n}\nclass Other\n" \
        "Dummy --> Other\n@enduml\n"
    end

    it "keeps the roomier default box" do
      expect(box.height).to eq(96.0)
    end
  end

  context "with a static member" do
    let(:source) do
      "@startuml\nclass Dummy {\n  {static} +count\n}\n@enduml\n"
    end

    it "underlines from the text, not the box edge" do
      underline = box.separators.last

      expect(underline.x1).to eq(box.x + 20.0)
    end
  end
end
