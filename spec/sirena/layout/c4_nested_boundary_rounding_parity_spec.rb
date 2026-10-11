# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4 do
  subject(:nodes) do
    source = File.read("spec/mermaid/c4/c4-8ab0b1ef.mmd")
    diagram = Sirena::Parser::C4.new.parse(source)
    flatten(described_class.new.call(diagram).children)
      .to_h { |node| [node.id, node] }
  end

  def flatten(items)
    items.flat_map { |item| [item, *flatten(item.children)] }
  end

  let(:widths) do
    %w[SystemB SystemD SystemG b2 b3].to_h do |id|
      [id, nodes.fetch(id).width]
    end
  end

  it "matches the pinned nested description and boundary widths" do
    expect(widths).to eq(
      "SystemB" => 398.0, "SystemD" => 338.0, "SystemG" => 338.0,
      "b2" => 498.0, "b3" => 438.0
    )
  end
end
