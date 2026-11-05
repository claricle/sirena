# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph/node_graph_helpers"

# Named notes as link ends, ports on a container frame, the grid unlinked
# items are packed into, and sources that drop to their nearest target, as
# the PlantUML JAR (1.2026.6) lays them out.
RSpec.describe Sirena::Notation::PlantUML::NodeGraph do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def graph_of(owner, body)
    owner.parse("@startuml\n#{body}\n@enduml\n").diagram
  end

  def boxes(owner, body)
    graph = graph_of(owner, body)
    placed = described_class::Layout.new.call(graph).placed
    placed.to_h { |box| [box.node.id, box] }
  end

  let(:usecase) { Sirena::Notation::PlantUML::Usecase }
  let(:component) { Sirena::Notation::PlantUML::Component }

  describe "a named note" do
    let(:body) do
      "(Start) as S\nnote \"one\\ntwo\" as N2\n(Use) as U\nS .. N2\nN2 .. U"
    end

    it "keeps the links written after its one-line declaration",
       :aggregate_failures do
      links = graph_of(usecase, body).edges.map { |e| [e.from.id, e.to.id] }

      expect(links).to eq([%w[S N2], %w[N2 U]])
    end

    it "takes its text from the quotes", :aggregate_failures do
      note = graph_of(usecase, body).nodes["N2"]

      expect(note.kind).to eq(:note)
      expect(note.lines).to eq(%w[one two])
    end

    it "still reads a multi-line note up to end note" do
      graph = graph_of(usecase, "note as N\n  a\n  b\nend note\nA --> B")

      expect([graph.nodes["N"].lines, graph.edges.size]).to eq([%w[a b], 1])
    end

    it "ranks the note between the notes it links", :aggregate_failures do
      at = boxes(usecase, body)

      expect(at["N2"].y).to be > at["S"].y
      expect(at["U"].y).to be > at["N2"].y
    end
  end

  describe "ports on a container" do
    let(:body) do
      "[i]\ncomponent C {\nportin p1\nportin p2\nportout po1\n" \
        "component c1\n}\n[o]\ni --> p1\ni --> p2\np1 --> c1\nc1 --> po1\n" \
        "po1 --> o"
    end
    let(:at) { boxes(component, body) }
    let(:frame) { at["C"] }

    def square(port)
      box = at[port]
      top = box.node.kind == :portin ? box.height - 12 : 0
      [box.y + top, box.y + top + 12]
    end

    it "straddles the top edge with an in port", :aggregate_failures do
      %w[p1 p2].each do |port|
        expect(square(port).sum / 2).to eq(frame.y)
      end
    end

    it "straddles the bottom edge with an out port" do
      expect(square("po1").sum / 2).to eq(frame.y + frame.height)
    end

    it "keeps the ports inside the frame's width", :aggregate_failures do
      %w[p1 p2 po1].each do |port|
        expect(at[port].x).to be >= frame.x
        expect(at[port].x + at[port].width).to be <= frame.x + frame.width
      end
    end

    it "spreads the ports along the edge", :aggregate_failures do
      expect(at["p1"].x).to be < at["p2"].x
      expect(at["p1"].x + at["p1"].width).to be <= at["p2"].x
    end

    it "keeps the other children inside, below the in ports",
       :aggregate_failures do
      expect(at["c1"].y).to be > frame.y
      expect(at["c1"].y + at["c1"].height).to be < frame.y + frame.height
    end

    it "ends a link at the port square, not at the label box" do
      graph = graph_of(component, body)
      scene = described_class::Layout.new.call(graph)
      route = scene.routes.find { |r| r.edge.to.id == "p1" }

      expect(route.points.last[1]).to be_within(0.01).of(square("p1").first)
    end

    it "ranks the container between the nodes outside it",
       :aggregate_failures do
      expect(frame.y).to be > at["i"].y
      expect(at["o"].y).to be > frame.y + frame.height
    end
  end

  describe "items with no link between them" do
    def placed_rows(count)
      names = (1..count).map { |n| "usecase U#{n}" }.join("\n")
      boxes(usecase, names).values.group_by(&:y).values.map(&:size)
    end

    it "pack into rows of ceil(sqrt(n))", :aggregate_failures do
      expect(placed_rows(2)).to eq([2])
      expect(placed_rows(3)).to eq([2, 1])
      expect(placed_rows(5)).to eq([3, 2])
      expect(placed_rows(10)).to eq([4, 4, 2])
    end

    it "pack into columns when left to right" do
      names = (1..5).map { |n| "usecase U#{n}" }.join("\n")
      at = boxes(usecase, "left to right direction\n#{names}")

      expect(at.values.group_by(&:x).values.map(&:size)).to eq([3, 2])
    end

    it "pack the same way inside a container" do
      names = (1..5).map { |n| "usecase U#{n}" }.join("\n")
      at = boxes(usecase, "rectangle R {\n#{names}\n}")

      expect(at.values.reject { |b| b.node.id == "R" }
        .group_by(&:y).values.map(&:size)).to eq([3, 2])
    end

    it "leave a linked pair alone", :aggregate_failures do
      at = boxes(usecase, "usecase A\nusecase B\nA --> B")

      expect(at["A"].x).to eq(at["B"].x)
      expect(at["B"].y).to be > at["A"].y
    end
  end

  describe "a source with slack" do
    let(:body) do
      "actor Admin\nusecase Use\nactor User\nusecase Start\n" \
        "User -> Start\nUser --> Use\nAdmin ---> Use"
    end

    it "drops to the rank just before its target, with its partner",
       :aggregate_failures do
      at = boxes(usecase, body)

      expect(at["Admin"].y).to be < at["User"].y
      expect(at["User"].y).to be < at["Use"].y
      expect(at["Start"].y).to be > at["Admin"].y
    end

    it "keeps a source whose link is already one rank long" do
      at = boxes(usecase, "actor X\nusecase U\nX --> U")

      expect(at["X"].y).to eq(16.0)
    end
  end
end
