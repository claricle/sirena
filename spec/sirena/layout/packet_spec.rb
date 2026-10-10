# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/packet"
require "sirena/diagram/packet"

RSpec.describe Sirena::Layout::Packet do
  subject(:scene) { described_class.new.to_graph(packet) }

  let(:packet) { Sirena::Diagram::Packet.new }

  it "returns the compact empty canvas" do
    expect([scene.class, scene.width, scene.height, scene.title,
            scene.fields, scene.bit_markers, scene.grid_lines.length])
      .to eq([described_class::Scene, 80.0, 80.0, nil, [], [], 34])
  end

  it "lays out shared pre-positioned IR identically to the private model" do
    packet.title = "Header"
    packet.add_field(Sirena::Diagram::PacketField.new(30, 34, "boundary"))
    ir = Sirena::Notation::Mermaid::IRAdapters::Packet.call(packet)
    actual = Marshal.dump(described_class.new.call(ir))

    expect(actual).to eq(Marshal.dump(scene))
  end

  context "with a title and one row" do
    before do
      packet.title = "Header"
      packet.add_field(Sirena::Diagram::PacketField.new(4, 7, "flags"))
    end

    it "includes title framing and complete canvas dimensions" do
      expect([scene.title.text, scene.title.x, scene.title.y,
              scene.width, scene.height, scene.bit_markers.length])
        .to eq(["Header", 520.0, 60.0, 1040.0, 210.0, 32])
    end

    it "positions a single-row field from its inclusive bit range" do
      field = scene.fields.first
      expect([field.box.x, field.box.y, field.box.width, field.box.height,
              field.label.text, field.range_label.text])
        .to eq([160.0, 130.0, 120.0, 40.0, "flags", "4-7"])
    end
  end

  context "with a field crossing a row boundary" do
    before do
      packet.add_field(Sirena::Diagram::PacketField.new(30, 34, "boundary"))
    end

    it "splits the field into labeled segments with exact bit ranges" do
      expect(scene.fields.map { |field| field_geometry(field) })
        .to eq([["boundary", 940.0, 70.0, 60.0, nil],
                ["boundary", 40.0, 110.0, 90.0, nil]])
    end

    it "sizes the untitled two-row canvas" do
      expect([scene.width, scene.height, scene.bit_markers.length])
        .to eq([1040.0, 190.0, 64])
    end
  end

  def field_geometry(field)
    [field.label.text, field.box.x, field.box.y, field.box.width,
     field.range_label&.text]
  end
end
