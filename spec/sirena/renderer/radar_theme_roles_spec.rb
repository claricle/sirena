# frozen_string_literal: true

require "spec_helper"
require "digest"

RSpec.describe Sirena::Renderer::Radar do
  let(:source) do
    <<~MERMAID
      radar-beta
        axis Speed, Quality, Cost
        curve Current{80, 70, 90}
    MERMAID
  end
  let(:default_signature) do
    ["54bcc35d8cfc250b8353cabf8d71e37a5cfa73ed69b47901f5b6139e4307c4d7",
     ["#2563eb", "#2563eb"]]
  end
  let(:dark_paints) do
    [["#1e1e1e"], ["#d4d4d4"], ["#2563eb", "#2563eb"]]
  end
  let(:partial_paints) do
    [[nil], [nil], ["#123456", "#123456"]]
  end

  def document(theme = nil)
    xml = Sirena::Engine.new(theme: theme).render(source)
    REXML::Document.new(xml)
  end

  def point_strokes(document)
    REXML::XPath.match(document, "//circle[@stroke-width='1']")
      .reject { |circle| circle.attributes["class"] == "radarGraticule" }
      .map { |circle| circle.attributes["stroke"] }
  end

  def label_fills(document)
    REXML::XPath.match(document, "//text").map do |text|
      text.attributes["fill"]
    end
  end

  def curve_paints(document)
    curve = REXML::XPath.first(document, "//path[@class='radarCurve-0']")
    [curve.attributes["fill"], curve.attributes["stroke"]]
  end

  def paints(document)
    [point_strokes(document).uniq, label_fills(document).uniq,
     curve_paints(document)]
  end

  it "preserves the exact default SVG and categorical palette" do
    xml = Sirena::Engine.new.render(source)
    signature = [Digest::SHA256.hexdigest(xml),
                 curve_paints(REXML::Document.new(xml))]

    expect(signature).to eq(default_signature)
  end

  it "uses dark background and label roles without changing the palette" do
    expect(paints(document(:dark))).to eq(dark_paints)
  end

  it "leaves unset scalar roles unpainted while retaining a supplied palette" do
    theme = Sirena::Theme.new(colors: { radar_palette: ["#123456"] })

    expect(paints(document(theme))).to eq(partial_paints)
  end
end
