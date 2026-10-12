# frozen_string_literal: true

# flowchart/flow-1d737c39.mmd: a cycle a_a -> b_b -> c_c -> a_a beside a
# longer path a_a -> c -> d_d -> c_c. dagre sinks b_b to the row above
# c_c and keeps the longer path straight, with b_b's chain on its left.
# Positions are read off the mmdc SVG for the same source.
RSpec.describe Sirena::Layout::Flowchart do
  let(:source) do
    "graph TB\n  a_a(Aftonbladet) --> b_b[gorilla] --> c_c{chimp} --> a_a\n  " \
      "a_a --> c --> d_d --> c_c\n"
  end
  let(:nodes) do
    model = Sirena::Parser::Flowchart.new.parse(source)
    described_class.new.call(model).children.to_h { |node| [node.id, node] }
  end
  let(:centres) do
    nodes.transform_values { |node| node.x + (node.width / 2.0) }
  end

  it "puts b_b on the row above c_c, beside d_d" do
    expect(nodes.fetch("b_b").y).to eq(nodes.fetch("d_d").y)
  end

  it "keeps the longer path on one centre line" do
    expect(centres.values_at("a_a", "c", "d_d", "c_c"))
      .to all(be_within(1).of(centres.fetch("a_a")))
  end

  it "places every node where mmdc does" do
    expect(nodes.transform_values { |node| [centres[node.id], node.y] })
      .to match(
        "a_a" => [be_within(1).of(206.36), be_within(1).of(8)],
        "b_b" => [be_within(1).of(60.63), be_within(1).of(216)],
        "c" => [be_within(1).of(206.36), be_within(1).of(112)],
        "d_d" => [be_within(1).of(206.36), be_within(1).of(216)],
        "c_c" => [be_within(1).of(206.86), be_within(1).of(320)],
      )
  end
end
