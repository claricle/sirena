# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/packet"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Packet do
  let(:diagram) do
    Sirena::Diagram::Packet.new.tap do |packet|
      packet.id = "field_0"
      packet.title = "Header"
      packet.add_field(Sirena::Diagram::PacketField.new(30, 34, "boundary"))
      packet.add_field(Sirena::Diagram::PacketField.new(4, 7, "flags"))
    end
  end
  let(:ir) { described_class.call(diagram) }

  it "produces valid collision-free pre-positioned IR" do
    expect(ir).to be_valid
  end

  it "preserves field order as bit starts and inclusive spans" do
    expect([ir.id, ir.label, ir.role, item_signatures])
      .to eq(expected_signature)
  end

  def item_signatures
    ir.items.map do |item|
      placement = item.placements.first
      [item.id, item.label, item.role, placement.dimension,
       placement.ordinal, placement.value.value, placement.span.value]
    end
  end

  def expected_signature
    ["field_0", "Header", "bit_grid",
     [["field_0_2", "boundary", "field", "bit", 0, 30.0, 5.0],
      ["field_1", "flags", "field", "bit", 1, 4.0, 4.0]]]
  end
end
