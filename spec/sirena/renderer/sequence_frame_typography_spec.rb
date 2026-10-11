# frozen_string_literal: true

require "spec_helper"
require "digest"

RSpec.describe Sirena::Renderer::Sequence do
  subject(:scene) do
    theme = Sirena::Theme::Registry.get(:default)
    Sirena::Layout::Sequence.new.call(parsed_diagram, theme: theme)
  end

  let(:source) do
    <<~MERMAID
      sequenceDiagram
      box Aqua Services
      participant A
      participant B
      end
      alt Ready
      A->>B: go
      else Wait
      B->>A: hold
      end
    MERMAID
  end
  let(:parsed_diagram) { Sirena::Parser::Sequence.new.parse(source) }
  let(:theme_evidence) do
    lambda do |selected, size, family|
      themed = Sirena::Layout::Sequence.new.call(
        parsed_diagram, theme: selected
      )
      xml = described_class.new(theme: selected).render(themed).to_xml
      frame = themed.frames.first
      box = themed.boxes.first
      [frame.font_size, frame.font_family, box.font_size, box.font_family,
       xml.scan(%(font-size="#{size}")).length,
       xml.scan(%(font-family="#{family}")).length]
    end
  end
  let(:mutated_typography_evidence) do
    frame = scene.frames.fetch(0)
    box = scene.boxes.fetch(0)
    frame.font_size = 27.5
    frame.font_family = "Frame Scene"
    box.font_size = 19.5
    box.font_family = "Box Scene"
    theme = Sirena::Theme::Registry.get(:default)
    xml = described_class.new(theme: theme).render(scene).to_xml
    [xml.scan('font-size="27.5"').length,
     xml.scan('font-family="Frame Scene"').length,
     xml.scan('font-size="19.5"').length,
     xml.scan('font-family="Box Scene"').length]
  end
  let(:direct_fallback_evidence) do
    boxes = [{ members: ["A"], title: "Group", color: nil }]
    placement = Sirena::Layout::Sequence::FramePlacement.new(
      boxes: boxes, ids: ["A"],
    )
    positions = { "A" => { x: 50.0 } }
    fallback = placement.box_shapes(positions, { "A" => 150.0 }, 200.0).first
    [fallback.font_size, fallback.font_family]
  end

  it "preserves the default frame SVG bytes" do
    digest = Digest::SHA256.hexdigest(Sirena::Engine.new.render(source))
    expected = "5ef1d427f974b2fc33e0cb4cb231e72e" \
               "9d8077d2faa9ea04e4906a6fc2acedc0"

    expect(digest).to eq(expected)
  end

  it "publishes the legacy default typography in typed shapes" do
    frame = scene.frames.fetch(0)
    box = scene.boxes.fetch(0)

    expect([[frame.font_size, frame.font_family],
            [box.font_size, box.font_family]])
      .to eq([[16.0, "Arial, sans-serif"], [16.0, "Arial, sans-serif"]])
  end

  it "publishes high-contrast Sequence typography in Scene and SVG" do
    contrast = Sirena::Theme::Registry.get(:high_contrast)
    family = "Arial, Helvetica, sans-serif"

    expect(theme_evidence.call(contrast, "18", family))
      .to eq([18.0, family, 18.0, family, 8, 4])
  end

  it "uses custom Sequence typography for every control-frame label" do
    values = { sequence_font_size: 22.0, font_family: "Fira Sans" }
    typography = Sirena::Theme::Typography.new(**values)
    custom = Sirena::Theme.new(typography: typography)

    expect(theme_evidence.call(custom, "22", "Fira Sans"))
      .to eq([22.0, "Fira Sans", 22.0, "Fira Sans", 8, 4])
  end

  it "falls back for an explicitly empty typography object" do
    empty = Sirena::Theme.new(typography: Sirena::Theme::Typography.new)

    expect(theme_evidence.call(empty, "16", "Arial, sans-serif"))
      .to eq([16.0, "Arial, sans-serif", 16.0, "Arial, sans-serif", 8, 8])
  end

  it "serializes typography from each typed shape without inference" do
    expect(mutated_typography_evidence).to eq([3, 3, 1, 1])
  end

  it "retains FramePlacement defaults for direct callers" do
    expect(direct_fallback_evidence).to eq([16.0, "Arial, sans-serif"])
  end
end
