# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassNamespaceNodes do
  subject(:layout) do
    described_class.new(size: ->(title) { { width: title.length * 10, height: 16 } })
  end

  let(:nodes) do
    [
      { id: "A", x: 10, y: 20, width: 120, height: 70 },
      { id: "B", x: 150, y: 20, width: 120, height: 70 },
      { id: "C", x: 500, y: 30, width: 120, height: 70 },
    ]
  end
  let(:namespaces) do
    [
      Sirena::Diagram::ClassNamespace.new(name: "Group", class_ids: %w[A B]),
      Sirena::Diagram::ClassNamespace.new(name: "Empty", class_ids: []),
    ]
  end
  let(:nested) { layout.nest(nodes, namespaces) }

  it "collapses namespace members once and keeps an empty namespace leaf" do
    shape = nested.map do |node|
      [node[:id], Array(node[:children]).map { |child| child[:id] }]
    end

    expect(shape).to eq(
      [["namespace:Group", %w[A B]], ["C", []], ["namespace:Empty", []]],
    )
  end

  it "flattens titled clusters and their members into canvas coordinates" do
    cluster, plain, empty = nested
    placed = [cluster.merge(x: 100, y: 200, width: 300, height: 160),
              plain, empty.merge(x: 20, y: 400)]
    flattened, boxes = layout.flatten(placed)

    result = [
      flattened.map { |node| [node[:id], node[:x], node[:y]] },
      boxes.map { |box| [box.id, box.title, box.x, box.y] },
    ]
    expect(result).to eq(
      [[["A", 110, 220], ["B", 250, 220], ["C", 500, 30]],
       [["namespace:Group", "Group", 100.0, 200.0],
        ["namespace:Empty", "Empty", 20.0, 400.0]]],
    )
  end
end
