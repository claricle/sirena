# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Packet do
  subject(:layout) { described_class.new }

  def titled_empty_scene
    diagram = Sirena::Diagram::Packet.new
    diagram.title = "Empty header"
    layout.call(diagram)
  end

  def narrow_field_scene
    diagram = Sirena::Diagram::Packet.new
    diagram.add_field(Sirena::Diagram::PacketField.new(0, 0, "flag"))
    layout.call(diagram)
  end

  it "retains title framing on an empty packet" do
    scene = titled_empty_scene
    expect([scene.width, scene.height, scene.title.text, scene.title.y,
            scene.fields])
      .to eq([1026.0, 47.0, "Empty header", 23.5, []])
  end

  it "numbers a one-bit field once, centred over its block" do
    field = narrow_field_scene.fields.fetch(0)
    expect([field.box.width, field.label.text, field.start_label.text,
            field.start_label.x, field.start_label.text_anchor,
            field.end_label]).to eq([27.0, "flag", "0", 14.5, "middle", nil])
  end
end
