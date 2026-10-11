# frozen_string_literal: true

require "spec_helper"

# typed_edges and inset_point are private and no parse reaches their
# degenerate inputs (every connection comes from a parsed node pair and
# cose never stacks two centres), so these examples call them directly.
RSpec.describe Sirena::Layout::Mindmap do
  subject(:layout) { described_class.new }

  describe "edges" do
    let(:scene) do
      diagram = Sirena::Parser::Mindmap.new.parse("mindmap\n  root\n    a\n")
      layout.call(diagram)
    end
    let(:nodes) { scene.children }

    it "drops a connection whose target node does not exist" do
      connections = [{ from: nodes.first.id, to: "ghost" }]

      expect(layout.send(:typed_edges, connections, nodes))
        .to eq([])
    end

    it "drops a connection whose source node does not exist" do
      connections = [{ from: "ghost", to: nodes.first.id }]

      expect(layout.send(:typed_edges, connections, nodes))
        .to eq([])
    end

    it "keeps a connection between two known nodes" do
      connections = [{ from: nodes[0].id, to: nodes[1].id }]

      expect(layout.send(:typed_edges, connections, nodes).size)
        .to eq(1)
    end
  end

  describe "#inset_point" do
    it "stays on the centre when both ends coincide" do
      point = layout.send(:inset_point, [10.0, 20.0], [10.0, 20.0])

      expect([point.x, point.y]).to eq([10.0, 20.0])
    end
  end
end
