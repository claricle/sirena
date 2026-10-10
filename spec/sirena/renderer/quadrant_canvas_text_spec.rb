# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Renderer::Quadrant do
  def label(text, x:, y:, rotation: nil)
    Sirena::Layout::Quadrant::Label.new(
      text: text, x: x, y: y, rotation: rotation, font_size: 16,
    )
  end

  def text_geometry(scene)
    document = REXML::Document.new(described_class.new.render(scene).to_xml)
    geometry_attributes = %w[x y transform]
    REXML::XPath.match(document, "//text").to_h do |text|
      attributes = text.attributes
      [text.text, geometry_attributes.map { |name| attributes[name] }]
    end
  end

  it "writes final canvas coordinates and rotates around the label anchor" do
    scene = Sirena::Layout::Quadrant::Scene.new(
      width: 200, height: 100,
      title: label("Title", x: 50, y: 15),
      axis_labels: [label("Vertical", x: 12, y: 30, rotation: -90)]
    )

    expect(text_geometry(scene)).to eq(
      "Title" => ["50.0", "15.0", nil],
      "Vertical" => ["12.0", "30.0", "rotate(-90 12 30)"],
    )
  end
end
