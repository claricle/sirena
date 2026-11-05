# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# PlantUML 1.2026.6's drawing of a state diagram, measured from its SVG:
# folded notes with a tail, history circles, divided states, curved
# transitions and `scale`.
RSpec.describe Sirena::Notation::PlantUML::State do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:svg) { Sirena.render(source) }
  let(:root) { REXML::Document.new(svg).root }

  def nodes(name, scope = root)
    REXML::XPath.match(scope, ".//*[local-name()='#{name}']")
  end

  def group(prefix)
    nodes("g").find { |item| item.attributes["id"].to_s.start_with?(prefix) }
  end

  def box(id)
    rect = nodes("rect", group("state-#{id}")).first
    %w[x y width height].map { |name| rect.attributes[name].to_f }
  end

  context "with a note beside a state" do
    let(:source) do
      "@startuml\n[*] --> A\nA --> B\nnote left of A : short\n" \
        "note right of B\n  two\n  lines\nend note\n@enduml"
    end

    let(:sheets) { nodes("path", group("state-A----note0")) }

    it "draws the note in PlantUML's pale yellow" do
      fills = sheets.map { |path| path.attributes["fill"] }
      expect(fills).to all(eq("#FEFFDD"))
    end

    it "draws the sheet and its folded corner as two paths" do
      expect(sheets.size).to eq(2)
    end

    it "draws a tail from the note to the state it annotates" do
      numbers = sheets.first.attributes["d"].scan(/-?\d+(?:\.\d+)?/)
      expect(numbers.map(&:to_f)).to include(box("A").first)
    end

    it "aligns the text of the note to its left edge" do
      anchors = nodes("text", group("state-B----note1")).map do |text|
        text.attributes["text-anchor"]
      end
      expect(anchors).to eq(%w[start start])
    end
  end

  context "with a plain state" do
    let(:source) { "@startuml\nstate A\nA --> B\n@enduml" }

    it "divides the name from the body with a line" do
      lines = nodes("line", group("state-A"))
      expect(lines.size).to eq(1)
    end

    it "is 50 high, as PlantUML draws an empty state" do
      expect(box("A")[3]).to eq(50.0)
    end
  end

  context "with history states" do
    let(:source) do
      "@startuml\nstate S {\n  [*] --> X\n  Y --> [H]\n  Z --> [H*]\n}\n@enduml"
    end

    it "draws H and H* as circles 22 across" do
      circles = nodes("circle").select { |c| c.attributes["r"] == "11.0" }
      expect(circles.size).to eq(2)
    end

    it "draws no box for them" do
      expect(nodes("rect", group("state-S_history"))).to be_empty
    end
  end

  context "with start and end markers" do
    let(:source) { "@startuml\n[*] --> A\nA --> [*]\n@enduml" }

    it "draws the start dot 10 in radius and the end ring 11" do
      radii = nodes("circle").map { |circle| circle.attributes["r"].to_f }
      expect(radii).to include(10.0, 11.0, 6.0)
    end
  end

  context "with transitions" do
    let(:source) do
      "@startuml\nstate A\nA --> B : go\nB --> A : back\n" \
        "A --> A : loop\n@enduml"
    end

    let(:paths) do
      edges = nodes("g").select do |item|
        item.attributes["id"].to_s.start_with?("transition-")
      end
      edges.map { |edge| nodes("path", edge).first.attributes["d"] }
    end

    it "draws them as curves, not as polylines" do
      expect(paths).to all(include("C"))
    end

    it "bows the two directions between a pair apart" do
      expect(paths.first(2).uniq.size).to eq(2)
    end
  end

  context "with `scale N width`" do
    let(:source) { "@startuml\nscale 350 width\n[*] --> A\nA --> B\n@enduml" }

    let(:viewbox) { root.attributes["viewBox"].split.map(&:to_f) }

    it "sizes the picture to that width" do
      expect(root.attributes["width"].to_f).to eq(350.0)
    end

    it "keeps the aspect and the drawing's own units" do
      expect(root.attributes["height"].to_f)
        .to be_within(0.01).of(350.0 * viewbox[3] / viewbox[2])
    end
  end

  context "with `scale N height` and a plain factor" do
    it "sizes to the height" do
      stub = "@startuml\nscale 200 height\n[*] --> A\nA --> B\n@enduml"
      doc = REXML::Document.new(Sirena.render(stub)).root
      expect(doc.attributes["height"].to_f).to eq(200.0)
    end

    it "multiplies by a factor" do
      doc = REXML::Document.new(
        Sirena.render("@startuml\nscale 2\n[*] --> A\nA --> B\n@enduml"),
      ).root
      view = doc.attributes["viewBox"].split.map(&:to_f)
      expect(doc.attributes["width"].to_f).to eq(view[2] * 2)
    end

    it "reads no scale from a diagram without one" do
      expect(described_class::Reader.scale_of("@startuml\nA --> B\n@enduml"))
        .to be_nil
    end
  end

  context "with a composite" do
    let(:source) { "@startuml\nstate S {\n  A --> B\n}\n@enduml" }

    it "keeps its name in a bar above the children" do
      parent = box("S")
      rule = nodes("line", group("state-S")).first
      expect(rule.attributes["y1"].to_f).to eq(parent[1] + 22.0)
    end
  end

  context "with two composites that lead to each other" do
    let(:source) do
      "@startuml\n[*] --> Entered\nstate Entered {\n  [*] --> Idle\n  " \
        "Idle --> Other\n  Other --> Idle\n}\n" \
        "state Other {\n  [*] --> Inner\n}\n@enduml"
    end

    it "keeps the composite no start marker enters at the top" do
      expect(box("Other")[1]).to be < box("Entered")[1]
    end

    it "stands the composite the start marker enters a rank below the other" do
      expect(box("Entered")[1] - box("Other")[1]).to eq(68.0)
    end

    it "draws the start marker's arrow down to the top of that composite" do
      path = nodes("path", group("transition-root_start_to_Entered")).first
      entered = box("Entered")
      ends = path.attributes["d"].scan(/-?\d+(?:\.\d+)?/).map(&:to_f).last(2)
      expect(ends.last).to be_within(1.0).of(entered[1])
    end
  end
end
