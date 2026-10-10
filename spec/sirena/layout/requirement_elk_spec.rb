# frozen_string_literal: true

require "digest"
require "spec_helper"

RSpec.describe Sirena::Layout::Requirement do
  let(:source) do
    <<~MERMAID
      requirementDiagram
        requirement r {
          id: R1
          text: Keep data
          risk: high
          verifymethod: test
        }
        element e {
          type: service
          docref: A1
        }
        e - satisfies -> r
    MERMAID
  end
  let(:diagram) { Sirena::Parser::Requirement.new.parse(source) }
  let(:layout) { described_class.new.tap { |instance| instance.placement = :elk } }
  let(:scene) { layout.call(diagram) }

  it "renders Requirement through the explicit ELK engine" do
    svg = Sirena.render(source, layout_engine: :elk)

    expect(svg).to include("<svg", "&lt;&lt;satisfies&gt;&gt;")
  end

  it "uses ELK node placement and routed sections in the typed Scene" do
    nodes = scene.children.to_h { |node| [node.id, node] }
    edge = scene.edges.fetch(0)

    expect([nodes.fetch("e").y < nodes.fetch("r").y, edge.path.include?(" L ")])
      .to eq([true, true])
  end

  it "keeps the default Requirement rendering byte-identical" do
    digest = Digest::SHA256.hexdigest(Sirena.render(source))

    expect(digest).to eq("cabcc7179b32df880a9c5e63e7102ed0bd3f0c9c9ade8b1795a79fc49afead96")
  end
end
