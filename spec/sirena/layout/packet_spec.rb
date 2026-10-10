# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/packet"
require "sirena/diagram/packet"

RSpec.describe Sirena::Layout::Packet do
  subject(:scene) { described_class.new.to_graph(packet) }

  let(:packet) { Sirena::Diagram::Packet.new }

  it "returns mmdc's empty canvas, one 15px padding strip" do
    expect([scene.class, scene.width, scene.height, scene.title,
            scene.fields])
      .to eq([described_class::Scene, 1026.0, 15.0, nil, []])
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
              scene.width, scene.height, scene.view_box])
        .to eq(["Header", 513.0, 70.5, 1026.0, 94.0, "0 0 1026 94"])
    end

    it "positions a single-row field from its inclusive bit range" do
      field = scene.fields.first
      expect([field.box.x, field.box.y, field.box.width, field.box.height,
              field.label.text, field.label.x, field.label.y])
        .to eq([129.0, 15.0, 123.0, 32.0, "flags", 190.5, 31.0])
    end

    it "numbers the first and last bit just above the block" do
      field = scene.fields.first
      expect(bit_labels(field))
        .to eq([["4", 129.0, 13.0, "start"], ["7", 252.0, 13.0, "end"]])
    end
  end

  context "with a field crossing a row boundary" do
    before do
      packet.add_field(Sirena::Diagram::PacketField.new(30, 34, "boundary"))
    end

    it "splits the field into labeled segments with exact bit ranges" do
      expect(scene.fields.map { |field| field_geometry(field) })
        .to eq([["boundary", 961.0, 15.0, 59.0, %w[30 31]],
                ["boundary", 1.0, 62.0, 91.0, %w[32 34]]])
    end

    it "sizes the untitled two-row canvas" do
      expect([scene.width, scene.height]).to eq([1026.0, 109.0])
    end
  end

  def field_geometry(field)
    [field.label.text, field.box.x, field.box.y, field.box.width,
     [field.start_label, field.end_label].map(&:text)]
  end

  def bit_labels(field)
    [field.start_label, field.end_label].map do |label|
      [label.text, label.x, label.y, label.text_anchor]
    end
  end
end
