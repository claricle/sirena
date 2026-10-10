# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/packet"

RSpec.describe Sirena::Diagram::Packet do
  describe Sirena::Diagram::PacketField do
    it "does not span rows when both endpoints share a row" do
      field = described_class.new(8, 15, "byte")

      expect([field.start_row, field.end_row, field.spans_rows?])
        .to eq([0, 0, false])
    end

    it "uses custom row boundaries when deciding whether it spans" do
      field = described_class.new(7, 8, "boundary")

      expect([field.spans_rows?(8), field.spans_rows?(16)])
        .to eq([true, false])
    end
  end
end
