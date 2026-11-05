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

    it "puts one beside the other" do
      expect(box("Right")[0]).to be >= box("Left")[2]
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
end
