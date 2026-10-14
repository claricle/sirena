# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Flowchart::LabelBackdropGeometry do
  let(:label) do
    Sirena::Layout::Flowchart::Label.new(
      text: "gyp", x: 100, y: 80, width: 40, height: 20, font_size: 20,
    )
  end
  let(:geometry) { label.backdrop_geometry(font_size: 20) }

  it "provides typed bounds around the measured baseline and descenders" do
    expect([geometry.class, geometry.x, geometry.y,
            geometry.width, geometry.height])
      .to eq([described_class, 77.5, 60.5, 45.0, 25.0])
  end

  context "with missing dimensions and typography metadata" do
    let(:label) { Sirena::Layout::Flowchart::Label.new(text: "x", x: 30, y: 70) }

    it "measures missing metrics using the caller's effective font size" do
      expect([geometry.x, geometry.y, geometry.width, geometry.height])
        .to eq([22.5, 50.5, 15.0, 25.0])
    end

    it "leaves the input label's metadata untouched" do
      geometry
      expect([label.width, label.height, label.font_size])
        .to eq([nil, nil, nil])
    end
  end
end
