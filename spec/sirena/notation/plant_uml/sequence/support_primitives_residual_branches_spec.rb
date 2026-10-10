# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence do
  let(:base_diagram) do
    described_class::Parser.new.parse(<<~PUML)
      @startuml
      A -> B
      @enduml
    PUML
  end

  it "rejects unknown settings and unsupported arrow combinations",
     :aggregate_failures do
    expect { described_class::Appearance.new(unknown: 1) }
      .to raise_error(ArgumentError, "unknown: [:unknown]")
    expect { described_class::HeadStyle.new(unknown: 1) }
      .to raise_error(ArgumentError, "unknown: [:unknown]")
    expect([described_class::ArrowSyntax.read("-"),
            described_class::ArrowSyntax.read("<->>")])
      .to eq([nil, nil])
  end

  it "draws rectangular notes and refuses an invalid head family" do
    outline = described_class::NoteShape.outline(:rnote, 1, 2, 10, 20)
    style = described_class::Style.read(
      "sequenceDiagram { participant { FontName invalid! } }",
    )

    expect([outline, style])
      .to eq(["M 1 2 L 11 2 L 11 22 L 1 22 Z", nil])
  end

  it "keeps absent arrow-end glyphs absent in shared IR" do
    style = described_class::ArrowStyle.new(
      head: described_class::ArrowEnd.new,
    )
    message = described_class::Message.new(
      from: "A", to: "B", label: "silent", style: style,
    )
    graph = described_class::IRAdapter.call(base_diagram.with_items([message]))

    expect(graph.edges.first.properties)
      .to have_attributes(source_marker: nil, target_marker: nil)
  end

  it "rebuilds defaults when optional setting details are absent" do
    graph = described_class::IRAdapter.call(base_diagram)
    missing_roles = %w[alignment legend_place]
    nodes = graph.nodes.reject do |node|
      missing_roles.include?(node.role)
    end
    stripped = Sirena::IR::Graph.new(
      id: graph.id, role: graph.role, nodes: nodes, edges: graph.edges,
    )
    rebuilt = described_class::IRReader.call(stripped)

    expect([rebuilt.appearance.alignment, rebuilt.chrome.legend_place])
      .to eq([:center, "bottom center"])
  end

  it "lays out an empty divider without a label box" do
    diagram = described_class::Parser.new.parse(<<~PUML)
      @startuml
      A -> B
      ====
      @enduml
    PUML
    graph = described_class::IRAdapter.call(diagram)
    divider = described_class::Layout.new.call(graph).dividers.first

    expect([divider.width, divider.texts]).to eq([0.0, []])
  end
end
