# frozen_string_literal: true

require "spec_helper"
require "digest"

RSpec.describe Sirena::Renderer::Radar do
  let(:dark_palette) do
    %w[#3794ff #858585 #4ec9b0 #f48771 #dcdcaa #89d185 #9cdcfe
       #969696 #fbbf24 #d4d4d4]
  end
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
    [["#e5e7eb"], ["#9ca3af"], ["#1e1e1e"], ["#d4d4d4"],
     ["#3794ff", "#3794ff"]]
  end
  let(:partial_paints) do
    [[nil], [nil], [nil], [nil], ["#123456", "#123456"]]
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

  def grid_strokes(document)
    REXML::XPath.match(document, "//*[@class='radarGraticule']")
      .map { |shape| shape.attributes["stroke"] }
  end

  def axis_strokes(document)
    REXML::XPath.match(document, "//line[@class='radarAxisLine']")
      .map { |line| line.attributes["stroke"] }
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
    [grid_strokes(document).uniq, axis_strokes(document).uniq,
     point_strokes(document).uniq, label_fills(document).uniq,
     curve_paints(document)]
  end

  it "preserves the exact default SVG and categorical palette" do
    xml = Sirena::Engine.new.render(source)
    signature = [Digest::SHA256.hexdigest(xml),
                 curve_paints(REXML::Document.new(xml))]

    expect(signature).to eq(default_signature)
  end

  it "uses dark background, label roles, and categorical palette" do
    expect(paints(document(:dark))).to eq(dark_paints)
  end

  it "consumes every dark curve colour in order" do
    curves = Array.new(10) do |index|
      "  curve c#{index}{#{index + 1}, #{index + 2}, #{index + 3}}"
    end
    palette_source = (["radar-beta", "  axis A, B, C"] + curves).join("\n")
    paths = REXML::XPath.match(document_for(palette_source, :dark), "//path")
      .select { |path| path.attributes["class"]&.start_with?("radarCurve-") }

    expect(paths.map do |path|
      [path.attributes["fill"],
       path.attributes["stroke"]]
    end)
      .to eq(dark_palette.map { |color| [color, color] })
  end

  it "leaves unset scalar roles unpainted while retaining a supplied palette" do
    theme = Sirena::Theme.new(colors: { radar_palette: ["#123456"] })

    expect(paints(document(theme))).to eq(partial_paints)
  end

  it "uses custom graticule and axis roles" do
    theme = Sirena::Theme.new(
      colors: {
        radar_grid_line: "#123456", radar_axis_line: "#abcdef",
        radar_palette: ["#654321"]
      },
    )

    expect(paints(document(theme)).first(2))
      .to eq([["#123456"], ["#abcdef"]])
  end

  def document_for(input, theme)
    REXML::Document.new(Sirena::Engine.new(theme: theme).render(input))
  end
end
