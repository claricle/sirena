# frozen_string_literal: true

require "spec_helper"
require "digest"

RSpec.describe Sirena::Renderer::Sequence do
  subject(:role_svgs) do
    renderer = described_class.new(theme: role_theme)
    inputs = fixture.values_at(:scene, :graph)
    inputs.map { |input| renderer.render(input).to_xml }
  end

  let(:fixture) do
    source = "sequenceDiagram\nactor Alice\nparticipant Bob\n" \
             "Alice->>Bob: hello\n"
    diagram = Sirena::Parser::Sequence.new.parse(source)
    { source: source, scene: Sirena::Layout::Sequence.new.call(diagram),
      graph: Sirena::Layout::Sequence.new.build_graph(diagram) }
  end
  let(:role_theme) do
    Sirena::Theme.new(
      colors: Sirena::Theme::ColorPalette.new(
        edge_stroke: "#111111", node_stroke: "#222222",
        node_fill: "#333333", label_text: "#444444"
      ),
    )
  end
  let(:default_digests) do
    %w[
      476c3544eec4e062740aceb28b6a53a93439ca072474f4662035d4bf033ce6fa
      c765fca366762aa4da6e92fea0ef33fc5925b984f0734435d6eacec20b4cd934
    ]
  end

  it "preserves default SVG bytes for typed and compatibility input" do
    typed = Sirena::Engine.new.render(fixture.fetch(:source))
    compatibility = described_class.new.render(fixture.fetch(:graph)).to_xml

    expect([typed, compatibility].map { |xml| Digest::SHA256.hexdigest(xml) })
      .to eq(default_digests)
  end

  it "uses the edge role for lifelines, messages, and arrowheads" do
    evidence = role_svgs.map do |xml|
      [xml.scan('stroke="#111111"').size, xml.scan('fill="#111111"').size]
    end
    expect(evidence).to eq([[4, 1], [4, 1]])
  end

  it "uses the node roles for participant boxes and actor outlines" do
    evidence = role_svgs.map do |xml|
      [xml.scan('stroke="#222222"').size, xml.scan('fill="#333333"').size]
    end
    expect(evidence).to eq([[6, 1], [6, 1]])
  end

  it "uses the label role for message and participant text" do
    role_svgs.each do |xml|
      expect(xml.scan('<text fill="#444444"').size).to eq(3)
    end
  end

  it "renders both input paths with the dark theme roles" do
    themed = Sirena::Engine.new(theme: :dark).render(fixture.fetch(:source))
    ordinary = Sirena::Engine.new.render(fixture.fetch(:source))
    colors = %w[#2d2d30 #858585 #d4d4d4]

    expect([themed, themed == ordinary]).to match([include(*colors), false])
  end
end
