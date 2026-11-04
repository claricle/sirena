# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph/node_graph_helpers"

RSpec.describe Sirena::Notation::PlantUML::Usecase do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def node(graph, id)
    graph.nodes.fetch(id)
  end

  describe "declarations" do
    it "reads an actor with an alias and a use case with an alias",
       :aggregate_failures do
      graph = parse(":Main Admin: as Admin\n(Use the app) as (Use)")

      expect(node(graph, "Admin").lines).to eq(["Main Admin"])
      expect([node(graph, "Admin").kind, node(graph, "Use").kind])
        .to eq(%i[actor usecase])
    end

    it "reads the actor and usecase keywords", :aggregate_failures do
      graph = parse("actor Bob\nactor \"Big Bob\" as B\nusecase UC1\n" \
                    "usecase \"Pay\" as P")

      expect(graph.nodes.values.map(&:kind)).to eq(%i[actor actor usecase
                                                      usecase])
      expect(node(graph, "B").lines).to eq(["Big Bob"])
    end

    it "reads a stereotype and a colour", :aggregate_failures do
      graph = parse("actor Bob <<Human>> #red")

      expect(node(graph, "Bob").stereotype).to eq("Human")
      expect(node(graph, "Bob").color).to eq("red")
    end

    it "reads a bare name with a stereotype as an actor" do
      expect(node(parse("User << Human >>"), "User").stereotype).to eq("Human")
    end
  end

  describe "links" do
    it "reads a labelled dashed arrow", :aggregate_failures do
      edge = parse("actor A\nA ..> (Use) : <<include>>").edges.first

      expect([edge.style, edge.head, edge.label])
        .to eq([:dashed, :target, "<<include>>"])
    end

    it "makes a node of an undeclared actor" do
      expect(parse("A -> (Use)").nodes["A"].kind).to eq(:actor)
    end

    it "reads a plain association without a head" do
      expect(parse("A -- (Use)").edges.first.head).to be_nil
    end
  end

  describe "containers and notes" do
    it "puts use cases inside a rectangle" do
      graph = parse("rectangle Shop {\n  (Buy)\n}\nactor C\nC --> (Buy)")

      expect(node(graph, "Buy").parent).to eq(node(graph, "Shop"))
    end

    it "reads a multi-line note attached to a node", :aggregate_failures do
      graph = parse("actor A\nnote right of A\n  one\n  two\nend note")

      note = graph.nodes.values.find { |n| n.kind == :note }
      expect(note.lines).to eq(%w[one two])
      expect(graph.edges.first.to).to eq(node(graph, "A"))
    end
  end

  describe "unsupported constructs" do
    it "names a style block" do
      expect { render("<style>\nx {}\n</style>\n(A)") }
        .to raise_unsupported("style block")
    end

    it "names an unknown statement" do
      expect { render("(A)\nwhat is this") }.to raise_unsupported("statement")
    end
  end

  describe "dispatch" do
    it "renders :Actor: lines as a use case diagram, not an activity" do
      expect(svg_texts(render(":Bob:\n(Use)\nBob --> (Use)")))
        .to include("Bob", "Use")
    end

    it "leaves an activity diagram alone" do
      expect(svg_texts(render("start\n:step;\nstop"))).to include("step")
    end

    it "leaves a sequence diagram with actors alone" do
      expect(svg_texts(render("actor A\nparticipant B\nA -> B : hi")))
        .to include("hi")
    end
  end
end
