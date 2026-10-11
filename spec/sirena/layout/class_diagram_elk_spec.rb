# frozen_string_literal: true

require "digest"
require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  let(:source) do
    <<~MERMAID
      classDiagram
        class Animal {
          +name: string
        }
        class Dog {
          +bark()
        }
        Animal <|-- Dog : owns
    MERMAID
  end
  let(:diagram) { Sirena::Parser::ClassDiagram.new.parse(source) }
  let(:layout) do
    described_class.new.tap { |instance| instance.placement = :elk }
  end
  let(:scene) { layout.call(diagram) }

  def elk_geometry
    nodes = scene.children.to_h { |node| [node.id, node] }
    edge = scene.edges.fetch(0)
    section = edge.sections.fetch(0)
    [nodes.fetch("Dog").y < nodes.fetch("Animal").y,
     [edge.source, edge.target], section.start_point.y < section.end_point.y,
     edge.sections.size]
  end

  it "renders Class Diagram through the explicit ELK engine" do
    allow(Sirena::Layout::ElkPlacement).to receive(:apply).and_call_original
    svg = Sirena.render(source, layout_engine: :elk)
    expect(svg).to include("<svg", "owns")
    expect(Sirena::Layout::ElkPlacement).to have_received(:apply).once
  end

  it "returns ELK node placement and routed typed edge sections" do
    expect(elk_geometry).to eq([true, %w[Dog Animal], true, 1])
  end

  it "keeps default Class Diagram rendering byte-identical" do
    digest = Digest::SHA256.hexdigest(Sirena.render(source))
    expect(digest).to eq("977bb42878889e5ab42d6c380c5580511eb4721ce9730bd54fcb989c22664b6f")
  end

  it "raises instead of falling back for a non-downward direction" do
    directed = source.sub("classDiagram", "classDiagram LR")
    expect { Sirena.render(directed, layout_engine: :elk) }
      .to raise_error(Sirena::Layout::LayoutError, /direction RIGHT/)
  end

  it "raises instead of flattening a namespace" do
    nested = "classDiagram\nnamespace N {\n class A\n}\n"
    expect { Sirena.render(nested, layout_engine: :elk) }
      .to raise_error(Sirena::Layout::LayoutError, /namespace/)
  end
end
