# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/packet"

RSpec.describe Sirena::Diagram::Packet do
  subject(:packet) { described_class.new }

  describe "packet dimensions" do
    it "uses one row and bit zero for an empty packet" do
      expect([packet.max_bit_position, packet.row_count, packet.row_count(8)]).to eq([0, 1, 1])
    end

    it "adds fields and derives the maximum bit and row counts" do
      packet.add_field(Sirena::Diagram::PacketField.new(0, 7, "header"))
      packet.add_field(Sirena::Diagram::PacketField.new(8, 39, "payload"))

      expect([packet.fields.map(&:label), packet.max_bit_position, packet.row_count, packet.row_count(16)]).to eq(
        [["header", "payload"], 39, 2, 3],
      )
    end
  end
end

RSpec.describe Sirena::Diagram::PacketField do
  subject(:field) { described_class.new("30", "34", "boundary") }

  it "coerces bit positions and reports its inclusive size" do
    expect([field.bit_start, field.bit_end, field.size]).to eq([30, 34, 5])
  end

  it "reports default row placement and spanning" do
    expect([field.start_row, field.end_row, field.spans_rows?]).to eq([0, 1, true])
  end

  it "reports row placement for a custom row width" do
    expect([field.start_row(16), field.end_row(16), field.spans_rows?(16)]).to eq([1, 2, true])
  end

  it "reports positions within default and custom rows" do
    expect([field.start_bit_in_row, field.end_bit_in_row,
            field.start_bit_in_row(16), field.end_bit_in_row(16)]).to eq([30, 2, 14, 2])
  end
end
