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
  let(:message_without_glyphs) do
    style = described_class::ArrowStyle.new(
      head: described_class::ArrowEnd.new,
    )
    described_class::Message.new(
      from: "A", to: "B", label: "silent", style: style,
    )
  end
  let(:properties_without_glyphs) do
    graph = described_class::IRAdapter.call(
      base_diagram.with_items([message_without_glyphs]),
    )
    graph.edges.first.properties
  end
  let(:rebuilt_without_optional_settings) do
    graph = described_class::IRAdapter.call(base_diagram)
    missing_roles = %w[alignment legend_place]
    nodes = graph.nodes.reject { |node| missing_roles.include?(node.role) }
    stripped = Sirena::IR::Graph.new(
      id: graph.id, role: graph.role, nodes: nodes, edges: graph.edges,
    )
    described_class::IRReader.call(stripped)
  end
  let(:empty_divider) do
    diagram = described_class::Parser.new.parse(<<~PUML)
      @startuml
      A -> B
      ====
      @enduml
    PUML
    graph = described_class::IRAdapter.call(diagram)
    described_class::Layout.new.call(graph).dividers.first
  end

  it "rejects unknown appearance settings" do
    expect { described_class::Appearance.new(unknown: 1) }
      .to raise_error(ArgumentError, "unknown: [:unknown]")
  end

  it "rejects unknown head-style settings" do
    expect { described_class::HeadStyle.new(unknown: 1) }
      .to raise_error(ArgumentError, "unknown: [:unknown]")
  end

  it "rejects unsupported arrow combinations" do
    arrows = [described_class::ArrowSyntax.read("-"),
              described_class::ArrowSyntax.read("<->>")]
    expect(arrows).to eq([nil, nil])
  end

  it "draws rectangular notes" do
    expect(described_class::NoteShape.outline(:rnote, 1, 2, 10, 20))
      .to eq("M 1 2 L 11 2 L 11 22 L 1 22 Z")
  end

  it "refuses an invalid head family" do
    style = described_class::Style.read(
      "sequenceDiagram { participant { FontName invalid! } }",
    )
    expect(style).to be_nil
  end

  it "keeps absent arrow-end glyphs absent in shared IR" do
    expect(properties_without_glyphs)
      .to have_attributes(source_marker: nil, target_marker: nil)
  end

  it "rebuilds defaults when optional setting details are absent" do
    expect([rebuilt_without_optional_settings.appearance.alignment,
            rebuilt_without_optional_settings.chrome.legend_place])
      .to eq([:center, "bottom center"])
  end

  it "lays out an empty divider without a label box" do
    expect([empty_divider.width, empty_divider.texts]).to eq([0.0, []])
  end
end
