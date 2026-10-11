# frozen_string_literal: true

# mmdc puts `a` above `b` in the sideways subgraph below: dagre re-adds the
# edge that ends on subgraph B after `a --> c`, so `a` is ordered first.
# Positions are read off the mmdc SVG for the same source.
RSpec.describe Sirena::Layout::Flowchart do
  let(:source) do
    "flowchart TB\n  subgraph A\n    b-->B\n    a\n  end\n  " \
      "a-->c\n  subgraph B\n    c\n  end\n"
  end
  let(:nodes) do
    model = Sirena::Parser::Flowchart.new.parse(source)
    described_class.new.call(model).children.first.children
      .to_h { |node| [node.id, node] }
  end

  it "orders the node with a plain edge above the one with a subgraph edge" do
    expect(nodes.fetch("a").y).to be < nodes.fetch("b").y
  end

  it "places both nodes where mmdc does" do
    expect([nodes.fetch("a").y, nodes.fetch("b").y])
      .to match([be_within(1).of(52), be_within(1).of(156)])
  end
end
