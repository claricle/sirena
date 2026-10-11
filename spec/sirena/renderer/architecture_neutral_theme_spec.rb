# frozen_string_literal: true

require "spec_helper"
require "digest"
require "rexml/document"

RSpec.describe Sirena::Renderer::Architecture do
  let(:source) do
    <<~MERMAID
      architecture-beta
        group api(cloud)[API]
        service a(server)[A] in api
        service b(database)[B]
        a:R -- L:b : HTTP
    MERMAID
  end
  let(:expected_builtin_paints) do
    {
      "default" => ["#f0f0f0", ["#666"]],
      "light" => ["#f0f0f0", ["#666"]],
      "dark" => ["#f0f0f0", ["#666"]],
      "high_contrast" => ["#f0f0f0", ["#666"]],
    }
  end
  let(:custom_theme) do
    Sirena::Theme.new(
      name: "custom",
      colors: Sirena::Theme::ColorPalette.new(
        group_background: "#123456", edge_color: "#abcdef",
      ),
    )
  end
  let(:partial_theme) do
    Sirena::Theme.new(
      name: "partial", colors: Sirena::Theme::ColorPalette.new,
    )
  end

  it "preserves the exact default render" do
    expect(Digest::SHA256.hexdigest(public_render("default")))
      .to eq("78c2d942f95dd1ccc623de80270e5e1a840a021ad945607d1563409e644751ad")
  end

  it "uses built-in group and neutral text roles" do
    actual = expected_builtin_paints.to_h do |name, _|
      [name, paints(public_render(name))]
    end
    expect(actual).to eq(expected_builtin_paints)
  end

  it "uses custom group and neutral text roles" do
    expect(paints(render_with(custom_theme)))
      .to eq(["#123456", ["#abcdef"]])
  end

  it "does not inject neutral paint into a scalar-empty partial theme" do
    expect(paints(render_with(partial_theme))).to eq([nil, [nil]])
  end

  def public_render(name)
    Sirena::Engine.new(theme: name).render(source)
  end

  def render_with(theme)
    diagram = Sirena::Parser::Architecture.new.parse(source)
    scene = Sirena::Layout::Architecture.new.call(diagram, theme: theme)
    described_class.new(theme: theme).render(scene).to_xml
  end

  def paints(xml)
    document = REXML::Document.new(xml)
    group = REXML::XPath.first(document, "//*[@id='group-api']/rect")
    neutral_text = %w[☁ ▦ ⬢ HTTP].map do |content|
      node = REXML::XPath.match(document, "//*[local-name()='text']")
        .find { |text| text.text == content }
      node.attributes["fill"]
    end
    [group.attributes["fill"], neutral_text.uniq]
  end
end
