# frozen_string_literal: true

require "digest"
require "spec_helper"

RSpec.describe Sirena::Layout::ErDiagram do
  let(:source) do
    <<~MERMAID
      erDiagram
        CUSTOMER ||--o{ ORDER : places
        ORDER ||--|{ LINE_ITEM : contains
    MERMAID
  end
  let(:diagram) { Sirena::Parser::ErDiagram.new.parse(source) }
  let(:layout) do
    described_class.new.tap { |instance| instance.placement = :elk }
  end
  let(:scene) { layout.call(diagram) }

  def entity(id)
    scene.children.find { |node| node.id == id }
  end

  def overlap?(first, second)
    first.x < second.x + second.width && second.x < first.x + first.width &&
      first.y < second.y + second.height && second.y < first.y + first.height
  end

  it "renders ER through the explicit ELK engine" do
    svg = Sirena.render(source, layout_engine: :elk)
    expect(svg).to include("<svg", "places", "contains")
  end

  it "routes the explicit engine through ELK placement" do
    allow(Sirena::Layout::ElkPlacement).to receive(:apply).and_call_original
    Sirena.render(source, layout_engine: :elk)
    expect(Sirena::Layout::ElkPlacement).to have_received(:apply).once
  end

  it "places the entities without overlap" do
    boxes = scene.children
    pairs = boxes.combination(2).select { |one, two| overlap?(one, two) }
    expect(pairs).to be_empty
  end

  it "connects each relationship to its own two entities" do
    expect(scene.edges.map { |edge| [edge.source, edge.target] })
      .to eq([%w[CUSTOMER ORDER], %w[ORDER LINE_ITEM]])
  end

  it "returns the sections ELK routed for each relationship" do
    expect(scene.edges.map { |edge| edge.sections.size }).to eq([1, 1])
  end

  it "lays the ELK chain out left to right" do
    expect(%w[CUSTOMER ORDER LINE_ITEM].map { |id| entity(id).x })
      .to eq(%w[CUSTOMER ORDER LINE_ITEM].map { |id| entity(id).x }.sort)
  end

  it "keeps default ER rendering byte-identical" do
    digest = Digest::SHA256.hexdigest(Sirena.render(source))
    expected = "5c1365669f3791ebed256448acd1496b" \
                 "68e069fba82fce26fa553b6e343d267a"
    expect(digest).to eq(expected)
  end

  it "raises instead of flattening a relationship to a missing entity" do
    graph = Sirena::Notation::Mermaid::IRAdapters::ErDiagram.call(diagram)
    graph.edges.first.target_id = "MISSING"
    expect { layout.scene(graph) }
      .to raise_error(Sirena::Layout::LayoutError, /missing entity/)
  end

  it "leaves the same dangling relationship to the grid by default" do
    graph = Sirena::Notation::Mermaid::IRAdapters::ErDiagram.call(diagram)
    graph.edges.first.target_id = "MISSING"
    expect { described_class.new.scene(graph) }.not_to raise_error
  end
end
