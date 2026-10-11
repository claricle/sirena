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
    [dog_above_animal?, edge_endpoints, route_descends?, elk_edge.sections.size]
  end

  def dog_above_animal?
    elk_node("Dog").y < elk_node("Animal").y
  end

  def elk_node(id)
    scene.children.find { |node| node.id == id }
  end

  def elk_edge
    scene.edges.fetch(0)
  end

  def edge_endpoints
    [elk_edge.source, elk_edge.target]
  end

  def route_descends?
    section = elk_edge.sections.fetch(0)
    section.start_point.y < section.end_point.y
  end

  it "renders Class Diagram through the explicit ELK engine" do
    svg = Sirena.render(source, layout_engine: :elk)
    expect(svg).to include("<svg", "owns")
  end

  it "routes the explicit engine through ELK placement" do
    allow(Sirena::Layout::ElkPlacement).to receive(:apply).and_call_original
    Sirena.render(source, layout_engine: :elk)
    expect(Sirena::Layout::ElkPlacement).to have_received(:apply).once
  end

  it "returns ELK node placement and routed typed edge sections" do
    expect(elk_geometry).to eq([true, %w[Dog Animal], true, 1])
  end

  it "keeps default Class Diagram rendering byte-identical" do
    digest = Digest::SHA256.hexdigest(Sirena.render(source))
    expected = "5b386c75b89ea54d1acd3a10ca62efde" \
               "77dda9729d207799525a08b7f299a985"
    expect(digest).to eq(expected)
  end

  it "renders a non-downward direction through explicit ELK" do
    directed = source.sub("classDiagram", "classDiagram LR")
    svg = Sirena.render(directed, layout_engine: :elk)
    expect(svg).to include('id="class-Animal"', 'id="class-Dog"')
  end

  it "raises instead of flattening a namespace" do
    nested = "classDiagram\nnamespace N {\n class A\n}\n"
    expect { Sirena.render(nested, layout_engine: :elk) }
      .to raise_error(Sirena::Layout::LayoutError, /namespace/)
  end
end
