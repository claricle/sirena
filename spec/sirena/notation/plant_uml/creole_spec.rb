# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Creole do
  def runs(text, **options)
    described_class.parse(text, **options).map { |r| [r.text, r.style] }
  end

  it "keeps a marker literal after a tilde" do
    expect(runs("~__not underlined__")).to eq([["__not underlined__", {}]])
  end

  it "keeps markers named in literal: as text even when paired",
     :aggregate_failures do
    expect(runs("__kept__", literal: ["__"])).to eq([["__kept__", {}]])
    expect(runs("__kept__")).to eq([["kept", { underline: true }]])
  end

  it "shows a math formula as monospace source with no tags" do
    expect(runs("see <math>x^2+y_1</math> now"))
      .to eq([["see ", {}], ["x^2+y_1", { mono: true }], [" now", {}]])
  end

  it "shows a latex formula the same way" do
    expect(runs("<latex>a_b</latex>")).to eq([["a_b", { mono: true }]])
  end

  it "shows an image it cannot load as monospace `(Cannot decode)`",
     :aggregate_failures do
    expected = [["by ", {}], ["(Cannot decode)", { mono: true }]]

    expect(runs("by <img sourceforge.jpg>")).to eq(expected)
    expect(runs("by <img:https://x.test/a.png>", inline: true))
      .to eq(expected)
  end

  it "reads a monospaced font tag as monospace and ignores other fonts" do
    node = Sirena::Svg::Text.new
    described_class.assign(node, "<font:monospaced>m</font> <font:Arial>a")

    expect(node.tspans.map { |t| [Array(t.content).join, t.font_family] })
      .to eq([["m", "monospace"], [" ", nil], ["a", nil]])
  end

  it "gives plain content the text with consumed tags removed" do
    node = Sirena::Svg::Text.new
    described_class.assign(node, "<back:orange>Orange")

    expect(Array(node.content)).to eq(["Orange"])
  end

  def decorations(text)
    described_class.parse(text).map do |run|
      described_class.decoration(run.style)
    end
  end

  it "draws ~~wave~~ as a wavy underline, as PlantUML does" do
    expect(decorations("a ~~wave~~ b")).to eq([nil, "wavy underline", nil])
  end

  it "draws <w> the same way" do
    expect(decorations("<w>wave</w>")).to eq(["wavy underline"])
  end

  it "keeps __underline__ a plain underline" do
    expect(decorations("__u__")).to eq(["underline"])
  end
end
