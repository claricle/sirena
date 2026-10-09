# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/packet"
require "sirena/diagram/packet"

RSpec.describe Sirena::Layout::Packet do
  subject(:graph) { described_class.new.to_graph(packet) }

  let(:packet) { Sirena::Diagram::Packet.new }

  it "returns the compact empty canvas" do
    expect(graph).to eq(
      fields: [], row_count: 0, bits_per_row: 32, cell_width: 30,
      cell_height: 40, padding: 40, header_height: 30, title_height: 0,
      title_margin: 0, width: 80, height: 80, title: nil
    )
  end

  context "with a title and one row" do
    before do
      packet.title = "Header"
      packet.add_field(Sirena::Diagram::PacketField.new(4, 7, "flags"))
    end

    it "includes title framing and complete canvas dimensions" do
      expect(graph).to include(
        title: "Header", title_height: 40, title_margin: 20,
        width: 1040, height: 210, row_count: 1
      )
    end

    it "positions a single-row field from its inclusive bit range" do
      expect(graph[:fields]).to contain_exactly(
        include(label: "flags", bit_start: 4, bit_end: 7, x: 160, y: 70,
                width: 120, height: 40, row: 0, start_col: 4, end_col: 7),
      )
    end
  end

  context "with a field crossing a row boundary" do
    let(:expected_segments) do
      [
        include(label: "boundary", bit_start: 30, bit_end: 31, row: 0,
                start_col: 30, end_col: 31, x: 940, y: 70, width: 60,
                is_continuation: false, is_final: false),
        include(label: "boundary", bit_start: 32, bit_end: 34, row: 1,
                start_col: 0, end_col: 2, x: 40, y: 110, width: 90,
                is_continuation: true, is_final: true),
      ]
    end

    before do
      packet.add_field(Sirena::Diagram::PacketField.new(30, 34, "boundary"))
    end

    it "splits the field into labeled segments with exact bit ranges" do
      expect(graph[:fields]).to match(expected_segments)
    end

    it "sizes the untitled two-row canvas" do
      expect(graph).to include(row_count: 2, width: 1040, height: 190,
                               title_height: 0, title_margin: 0)
    end
  end
end
