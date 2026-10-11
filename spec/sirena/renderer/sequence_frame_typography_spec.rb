# frozen_string_literal: true

require "spec_helper"
require "digest"

RSpec.describe Sirena::Renderer::Sequence do
  subject(:scene) do
    theme = Sirena::Theme::Registry.get(:default)
    diagram = Sirena::Parser::Sequence.new.parse(source)
    Sirena::Layout::Sequence.new.call(diagram, theme: theme)
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
  let(:theme_evidence) do
    lambda do |selected, size, family|
      diagram = Sirena::Parser::Sequence.new.parse(source)
      themed = Sirena::Layout::Sequence.new.call(
        diagram, theme: selected
      )
      xml = described_class.new(theme: selected).render(themed).to_xml
      frame = themed.frames.first
      box = themed.boxes.first
      [frame.font_size, box.font_size,
       frame.respond_to?(:font_family), box.respond_to?(:font_family),
       xml.scan(%(font-size="#{size}")).length,
       xml.scan(%(font-family="#{family}")).length]
    end
  end
  let(:mutated_typography_evidence) do
    frame = scene.frames.fetch(0)
    box = scene.boxes.fetch(0)
    frame.font_size = 27.5
    box.font_size = 19.5
    typography = Sirena::Theme::Typography.new(font_family: "Fira Sans")
    theme = Sirena::Theme.new(typography: typography)
    xml = described_class.new(theme: theme).render(scene).to_xml
    [xml.scan('font-size="27.5"').length,
     xml.scan('font-size="19.5"').length,
     xml.scan('font-family="Fira Sans"').length]
  end
  let(:direct_fallback_evidence) do
    boxes = [{ members: ["A"], title: "Group", color: nil }]
    placement = Sirena::Layout::Sequence::FramePlacement.new(
      boxes: boxes, ids: ["A"],
    )
    positions = { "A" => { x: 50.0 } }
    fallback = placement.box_shapes(positions, { "A" => 150.0 }, 200.0).first
    [fallback.font_size, fallback.respond_to?(:font_family)]
  end
  let(:default_render_evidence) do
    xml = Sirena::Engine.new.render(source)
    digest = Digest::SHA256.hexdigest(xml)
    family = 'font-family="Arial, sans-serif"'
    [digest, xml.scan(family).size]
  end

  it "renders registered-default family ownership" do
    expected = "5ef1d427f974b2fc33e0cb4cb231e72e" \
               "9d8077d2faa9ea04e4906a6fc2acedc0"

    expect(default_render_evidence).to eq([expected, 8])
  end

  it "publishes only the default measured size in typed shapes" do
    frame = scene.frames.fetch(0)
    box = scene.boxes.fetch(0)

    expect([[frame.font_size, frame.respond_to?(:font_family)],
            [box.font_size, box.respond_to?(:font_family)]])
      .to eq([[16.0, false], [16.0, false]])
  end

  it "publishes high-contrast Sequence typography in Scene and SVG" do
    contrast = Sirena::Theme::Registry.get(:high_contrast)
    family = "Arial, Helvetica, sans-serif"

    expect(theme_evidence.call(contrast, "18", family))
      .to eq([18.0, 18.0, false, false, 8, 4])
  end

  it "uses custom Sequence typography for every control-frame label" do
    values = { sequence_font_size: 22.0, font_family: "Fira Sans" }
    typography = Sirena::Theme::Typography.new(**values)
    custom = Sirena::Theme.new(typography: typography)

    expect(theme_evidence.call(custom, "22", "Fira Sans"))
      .to eq([22.0, 22.0, false, false, 8, 4])
  end

  it "falls back for an explicitly empty typography object" do
    empty = Sirena::Theme.new(typography: Sirena::Theme::Typography.new)

    expect(theme_evidence.call(empty, "16", "Arial, sans-serif"))
      .to eq([16.0, 16.0, false, false, 8, 8])
  end

  it "serializes Scene sizes and the renderer theme family" do
    expect(mutated_typography_evidence).to eq([3, 1, 4])
  end

  it "retains FramePlacement defaults for direct callers" do
    expect(direct_fallback_evidence).to eq([16.0, false])
  end
end
