# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph_helpers"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::Archimate do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:fixture) do
    File.expand_path(
      "../../../../fixtures/plantuml_entity_archimate/archimate_junctions.puml",
      __dir__,
    )
  end

  def graph_of(body)
    Sirena::Notation::PlantUML.parse("@startuml\n#{body}\n@enduml\n").diagram
  end

  def node(graph, id)
    graph.nodes.fetch(id)
  end

  describe "archimate diagrams" do
    it "reads a layer colour, dropping the stereotype", :aggregate_failures do
      vpn = node(graph_of("archimate #Technology \"VPN\" as v <<x-device>>\n" \
                          "rectangle R"), "v")

      expect([vpn.kind, vpn.lines, vpn.color, vpn.stereotype])
        .to eq([:archimate, ["VPN"], "C9FFC9", nil])
    end

    it "fills each layer as the JAR 1.2026.6 does" do
      jar = { "business" => "FFFFCC", "application" => "C2F0FF",
              "technology" => "C9FFC9", "physical" => "97FF97",
              "motivation" => "CCCCFF", "strategy" => "F8E7C0",
              "implementation" => "FFE0E0" }

      expect(jar.keys.to_h { |l| [l, described_class.color(l)] }).to eq(jar)
    end

    it "keeps an ordinary colour and survives no colour", :aggregate_failures do
      graph = graph_of("archimate #red \"A\" as a\narchimate \"B\" as b\n" \
                       "archimate #ABCDEF \"C\" as c")

      expect(%w[a b c].map { |id| node(graph, id).color })
        .to eq(["red", nil, "ABCDEF"])
    end

    it "reads a junction circle, named after its colour", :aggregate_failures do
      graph = graph_of("!define Or circle #black\nOr J\nrectangle R #red")

      expect([node(graph, "J").kind, node(graph, "J").color])
        .to eq([:circle, "black"])
      expect(node(graph, "R").color).to eq("red")
    end

    it "names a macro with parameters" do
      expect { graph_of("!define F(x) rectangle x\nrectangle A") }
        .to raise_unsupported("preprocessor")
    end

    it "is claimed as a component diagram" do
      parsed = Sirena::Notation::PlantUML.parse(
        "@startuml\narchimate #Business \"B\" as b\n@enduml\n",
      )

      expect(parsed.type).to eq(:component_diagram)
    end

    it "keeps an element named STOP out of the activity family" do
      body = "rectangle STOP\nrectangle START\nSTOP -up-> START"

      expect(Sirena::Notation::PlantUML.parse("@startuml\n#{body}\n@enduml\n")
        .type).to eq(:component_diagram)
    end

    it "still reads a lone start or stop as an activity" do
      expect(Sirena::Notation::PlantUML.parse("@startuml\nstart\n:a;\nstop\n" \
                                              "@enduml\n").type)
        .to eq(:activity_diagram)
    end
  end

  describe "rendering" do
    let(:svg) { Sirena.render(File.read(fixture), notation: :plantuml) }

    it "draws the whole fixture", :aggregate_failures do
      expect(svg_root(svg).name).to eq("svg")
      expect(svg_texts(svg))
        .to include("VPN Server", "GO", "STOP", "WAIT", "JunctionOr",
                    "JunctionAnd")
    end

    it "fills a layer element and a junction", :aggregate_failures do
      expect(svg).to include('fill="#C9FFC9"')
      expect(svg).to include('fill="black"').and include('fill="whitesmoke"')
    end
  end
end
