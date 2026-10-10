# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Block do
  subject(:diagram) { described_class.new }

  describe Sirena::Diagram::BlockNode do
    let(:space) { described_class.new(block_type: "space") }
    let(:arrow) { described_class.new(block_type: "arrow") }
    let(:plain) { described_class.new(block_type: "block") }

    it "classifies special block types" do
      expect([space.space?, arrow.arrow?, plain.space?, plain.arrow?])
        .to eq([true, true, false, false])
    end

    it "becomes compound when a child is added" do
      child = described_class.new(id: "child")
      node = described_class.new(id: "parent")
      node.add_child(child)
      expect([node.children, node.compound?]).to eq([[child], true])
    end
  end

  {
    block: [Sirena::Diagram::BlockNode, :blocks],
    connection: [Sirena::Diagram::BlockConnection, :connections],
  }.each do |kind, (model, collection)|
    it "appends #{kind} values" do
      item = model.new
      diagram.public_send("add_#{kind}", item)
      expect(diagram.public_send(collection)).to eq([item])
    end
  end

  it "is valid without content" do
    expect(diagram).to be_valid
  end
end
