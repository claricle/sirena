# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph/node_graph_helpers"

# The ranks and direction the PlantUML JAR (1.2026.6) gives use case,
# component and deployment diagrams: top to bottom unless told otherwise;
# `->` keeps the two ends in one rank, `-->` puts the target one rank on,
# `--->` two, and `-up->`/`-left->` read the link backwards.
RSpec.describe Sirena::Notation::PlantUML::NodeGraph do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def boxes(family, links, direction: nil)
    head, owner = if family == :usecase
                    ["actor A\nusecase B\nusecase C",
                     Sirena::Notation::PlantUML::Usecase]
                  else
                    ["component A\ncomponent B\ncomponent C",
                     Sirena::Notation::PlantUML::Component]
                  end
    source = "@startuml\n#{direction}\n#{head}\n#{links}\n@enduml\n"
    graph = owner.parse(source).diagram
    placed = described_class::Layout.new.call(graph).placed
    placed.to_h { |box| [box.node.id, box] }
  end

  %i[usecase component].each do |family|
    describe "a #{family} diagram" do
      let(:ltr) { "left to right direction" }

      it "stacks a fan out top to bottom by default", :aggregate_failures do
        at = boxes(family, "A --> B\nA --> C")

        expect(at["B"].y).to be > at["A"].y
        expect(at["B"].y).to eq(at["C"].y)
        expect(at["B"].x).not_to eq(at["C"].x)
      end

      it "runs ranks left to right under `left to right direction`",
         :aggregate_failures do
        at = boxes(family, "A --> B\nA --> C", direction: ltr)

        expect(at["B"].x).to be > at["A"].x
        expect(at["B"].x).to eq(at["C"].x)
      end

      it "keeps the ends of a one-dash link in one rank", :aggregate_failures do
        at = boxes(family, "A -> B\nB -> C")

        expect(at.values.map(&:y).uniq.size).to eq(1)
        expect(at["A"].x).to be < at["B"].x
        expect(at["B"].x).to be < at["C"].x
      end

      it "keeps a one-dash link in one column when left to right",
         :aggregate_failures do
        at = boxes(family, "A -> B\nB -> C", direction: ltr)

        expect(at.values.map(&:x).uniq.size).to eq(1)
        expect(at["A"].y).to be < at["B"].y
      end

      it "mixes link lengths: one dash stays, two dashes step on",
         :aggregate_failures do
        at = boxes(family, "A --> B\nB -> C")

        expect(at["B"].y).to be > at["A"].y
        expect(at["C"].y).to eq(at["B"].y)
      end

      it "steps two ranks for a three-dash link", :aggregate_failures do
        at = boxes(family, "A ---> B\nA --> C")

        expect(at["C"].y).to be > at["A"].y
        expect(at["B"].y).to be > at["C"].y
      end

      it "reads direction words: down steps on, right stays",
         :aggregate_failures do
        at = boxes(family, "A -right-> B\nA -down-> C")

        expect(at["B"].y).to eq(at["A"].y)
        expect(at["B"].x).to be > at["A"].x
        expect(at["C"].y).to be > at["A"].y
      end

      it "reads up and left backwards", :aggregate_failures do
        at = boxes(family, "A -up-> B\nA -left-> C")

        expect(at["B"].y).to be < at["A"].y
        expect(at["C"].y).to eq(at["A"].y)
        expect(at["C"].x).to be < at["A"].x
      end

      it "ranks by the written order, not by the arrow head" do
        at = boxes(family, "A <-- B")

        expect(at["B"].y).to be > at["A"].y
      end
    end
  end
end
