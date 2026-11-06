# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Where PlantUML's own layout (graphviz) puts the states, measured with the
# JAR on small diagrams: a single-dash arrow is drawn left to right on one
# rank, a note sits beside its target without moving it off its column, and
# composites whose ranks overlap stand side by side.
RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  let(:root) { REXML::Document.new(Sirena.render(source)).root }

  def group(id)
    REXML::XPath.match(root, "//*[local-name()='g']").find do |found|
      found.attributes["id"] == "state-#{id}"
    end
  end

  # [left, top, right, bottom] in the state's own group, which the renderer
  # places in absolute terms.
  def box(id)
    rect = REXML::XPath.first(group(id), "*[local-name()='rect']")
    x, y, w, h = %w[x y width height].map { |name| rect.attributes[name].to_f }
    [x, y, x + w, y + h]
  end

  def centre_x(id)
    box = box(id)
    (box.first + box[2]) / 2.0
  end

  def centre_y(id)
    box = box(id)
    (box[1] + box.last) / 2.0
  end

  context "with a note either side of a column of states" do
    let(:source) do
      <<~PUML
        @startuml
        [*] --> Active
        Active --> Inactive
        note left of Active : short
        note right of Inactive : a longer note here
        @enduml
      PUML
    end

    it "keeps the targets in one column, as PlantUML does" do
      expect(centre_x("Active")).to be_within(1.0).of(centre_x("Inactive"))
    end

    it "keeps Inactive below Active" do
      expect(box("Inactive")[1]).to be > box("Active").last
    end
  end

  context "with single-dash and double-dash arrows" do
    let(:source) do
      <<~PUML
        @startuml
        [*] --> S1
        S1 --> S2
        S2 -> S3
        S3 --> S4
        @enduml
      PUML
    end

    it "draws a single-dash arrow on one rank" do
      expect(centre_y("S2")).to be_within(1.0).of(centre_y("S3"))
    end

    it "draws a single-dash arrow left to right" do
      expect(box("S3").first).to be > box("S2")[2]
    end

    it "draws a double-dash arrow down a rank" do
      expect(box("S4")[1]).to be > box("S3").last
    end
  end

  context "with a single-dash arrow out of the initial marker" do
    let(:source) do
      <<~PUML
        @startuml
        [*] -> State1
        State1 --> State2
        @enduml
      PUML
    end

    it "puts State1 beside the marker" do
      marker = REXML::XPath.match(root, "//*[local-name()='circle']").first
      expect(marker.attributes["cy"].to_f)
        .to be_within(1.0).of(centre_y("State1"))
    end
  end

  context "with two composites that only reach one another through a cycle" do
    let(:source) do
      <<~PUML
        @startuml
        [*] --> Left
        state Left {
          [*] --> Idle
          Idle --> Right : go
          Right --> Idle : back
        }
        state Right {
          [*] --> A
          A --> B
          B --> C
        }
        @enduml
      PUML
    end

    it "puts them on shared ranks" do
      expect(box("Right")[1]).to be < box("Left").last
    end

    it "puts the later-listed one on the left, as PlantUML does" do
      expect(box("Left")[0]).to be >= box("Right")[2]
    end
  end

  context "with composites joined by a plain transition" do
    let(:source) do
      <<~PUML
        @startuml
        state A {
          [*] --> a1
        }
        state B {
          [*] --> b1
        }
        A --> B
        @enduml
      PUML
    end

    it "stacks them, as PlantUML does" do
      expect(box("B")[1]).to be > box("A").last
    end
  end

  def circles
    REXML::XPath.match(root, "//*[local-name()='circle']").map do |circle|
      [circle.attributes["cx"].to_f, circle.attributes["cy"].to_f]
    end
  end

  context "with two states joined both ways, one way twice" do
    let(:source) do
      <<~PUML
        @startuml
        [*] --> Low
        Low --> High : up
        High --> Low : down
        High --> Low : again
        @enduml
      PUML
    end

    it "ranks them by the way most transitions run" do
      expect(box("High")[1]).to be < box("Low")[1]
    end
  end

  context "with two states joined one way each" do
    let(:source) do
      "@startuml\n[*] --> A\nA --> B\nB --> A\n@enduml"
    end

    it "keeps the first listed on top" do
      expect(box("A")[1]).to be < box("B")[1]
    end
  end

  context "with a start marker entering the composite that stands lower" do
    let(:source) do
      <<~PUML
        @startuml
        [*] --> Lower
        state Upper {
          [*] --> Idle
          Idle --> Lower : go
        }
        state Lower {
          [*] --> Busy
          Busy --> Upper : back
        }
        @enduml
      PUML
    end

    it "hangs the marker straight above it" do
      x, = circles.min_by { |circle| circle[1] }
      expect(x).to be_within(0.5).of(centre_x("Lower"))
    end
  end

  context "with an end marker a composite leads to" do
    let(:source) do
      <<~PUML
        @startuml
        state Box {
          [*] --> First
          First --> Second
        }
        Box --> [*] : done
        @enduml
      PUML
    end

    it "stands beside the composite, right of it" do
      marker = circles.max_by(&:first)
      expect(marker.first).to be > box("Box")[2]
    end

    it "is level with the state its start marker enters" do
      marker = circles.max_by(&:first)
      expect(marker[1]).to be_within(0.5).of(centre_y("First"))
    end
  end

  context "with an end marker a composite without a start marker leads to" do
    let(:source) do
      "@startuml\nstate Box {\n  First --> Second\n}\nBox --> [*]\n@enduml"
    end

    it "keeps the marker below the composite" do
      expect(circles.first[1]).to be > box("Box").last
    end
  end

  context "with a transition from a composite to itself" do
    let(:source) do
      <<~PUML
        @startuml
        state Box {
          [*] --> First
          First --> Second
          Second --> Third
          Third --> Fourth
        }
        Box --> Box : retry
        @enduml
      PUML
    end

    it "loops level with the start marker, its first row" do
      loop_line = REXML::XPath.match(root, "//*[local-name()='path']").last
      numbers = loop_line.attributes["d"].scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
      ys = numbers.each_slice(2).map(&:last)
      expect(ys).to include(a_value_within(12.0).of(circles.first[1]))
    end
  end

  context "with the labels of a composite's transitions" do
    let(:source) do
      <<~PUML
        @startuml
        state Wide {
          [*] --> Top
          Top --> Bottom : a long label for the first transition
          Top --> Bottom : a second long label beside it
        }
        state Plain {
          [*] --> One
          One --> Two
        }
        @enduml
      PUML
    end

    def width_of(id)
      box = box(id)
      box[2] - box[0]
    end

    # Graphviz gives each label a node of its own rank, so the two labels
    # stand side by side and the cluster grows to hold them (JAR 1.2026.6:
    # a composite 263.2 wide around one 213-wide label).
    it "widens the composite to hold the labels of one rank side by side" do
      labels = REXML::XPath.match(root, "//*[local-name()='text']")
        .select { |text| text.text.to_s.include?("label") }
      estimate = labels.sum { |text| text.text.size * 5.0 }
      expect(width_of("Wide")).to be > estimate
    end

    it "leaves a composite with no labelled transitions at its content width" do
      expect(width_of("Plain")).to be < 120
    end
  end

  context "with composites that stand side by side" do
    let(:source) do
      <<~PUML
        @startuml
        state Left {
          [*] --> Idle
          Idle --> Right
          Right --> Idle
        }
        state Right {
          [*] --> One
          One --> Two
        }
        @enduml
      PUML
    end

    # JAR 1.2026.6 keeps 24 between two composites on one rank; the layout
    # engine's own spacing is 60.
    it "keeps 24 between them" do
      gap = [box("Right")[0] - box("Left")[2], box("Left")[0] - box("Right")[2]]
      expect(gap.max).to be_within(0.5).of(24)
    end
  end

  # JAR 1.2026.6: 24 right and 13 below a composite's children with nothing
  # at its border, 16 on both with a transition out of a child, and 24 with
  # that and a transition ending at the composite.
  describe "the room a composite keeps round its children" do
    let(:source) do
      <<~PUML
        @startuml
        #{border}
        state "A title far longer than the one state it holds, to set the width" as Box {
          state Inner
        }
        @enduml
      PUML
    end

    def room
      [box("Box")[2] - box("Inner")[2], box("Box")[3] - box("Inner")[3]]
    end

    context "with nothing at the border" do
      let(:border) { "" }

      it "keeps 13 below" do
        expect(room.last).to eq(13.0)
      end
    end

    context "with a transition out of a child" do
      let(:border) { "Inner --> Elsewhere" }

      it "keeps 16 below" do
        expect(room.last).to eq(16.0)
      end
    end

    context "with that and a transition into the composite" do
      let(:border) { "[*] --> Box\nInner --> Elsewhere" }

      it "keeps 24 below" do
        expect(room.last).to eq(24.0)
      end
    end
  end

  # JAR 1.2026.6 keeps 20 beside the title of a composite with nothing at
  # its border and about 15.5 beside any other.
  describe "the room beside a composite title" do
    def width_with(border)
      svg = Sirena.render(<<~PUML)
        @startuml
        #{border}
        state "A title far longer than the one state it holds, to set the width" as Box {
          state Inner
        }
        @enduml
      PUML
      rect = REXML::XPath.first(REXML::Document.new(svg).root,
                                "//*[@id='state-Box']/*[local-name()='rect']")
      rect.attributes["width"].to_f
    end

    it "is smaller when a transition crosses the border" do
      expect(width_with("") - width_with("Inner --> Elsewhere"))
        .to be_within(0.01).of(4.5)
    end
  end
end
