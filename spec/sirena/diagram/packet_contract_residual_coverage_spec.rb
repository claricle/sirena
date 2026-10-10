# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/packet"

RSpec.describe Sirena::Diagram::Packet do
  it "identifies an empty packet as a valid packet diagram" do
    packet = described_class.new

    expect([packet.diagram_type, packet.valid?]).to eq([:packet, true])
  end
end
