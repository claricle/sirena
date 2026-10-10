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
    expect([scene.width, scene.height, scene.title.text, scene.fields,
            scene.bit_markers, scene.grid_lines.length])
      .to eq([80.0, 140.0, "Empty header", [], [], 34])
  end

  it "omits a bit-range label when a field is too narrow" do
    scene = narrow_field_scene
    field = scene.fields.fetch(0)
    expect([field.box.width, field.label.text, field.range_label,
            scene.bit_markers.length]).to eq([30.0, "flag", nil, 32])
  end
end
