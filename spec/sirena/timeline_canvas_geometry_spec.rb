# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Layout::TimelineCard, "#place" do
  include TimelineSceneHelpers

  let(:source) do
    "timeline\n section a\n 2020 : Machinery, Water power, Steam <br>power\n"
  end
  let(:scene) { lay_out(source) }
  let(:card) { cards_of(scene, "period").first }
  let(:doc) do
    REXML::Document.new(Sirena::Renderer::Timeline.new.render(scene).to_xml)
  end

  def attribute_of(path, name)
    REXML::XPath.first(doc, path).attributes[name]
  end

  it "publishes the box outline on the canvas" do
    expect(card.outline)
      .to eq("M100 230.6 v-57.8 q0,-5 5,-5 h180 q5,0 5,5 v62.8 H100 Z")
  end

  it "publishes the rule along the card's bottom edge" do
    expect([card.rule.x1, card.rule.x2, card.rule.y1])
      .to eq([card.x, card.x + card.width, card.y + card.height])
  end

  it "publishes the text anchor at the card's horizontal centre" do
    expect(card.text_x).to eq(card.x + (card.width / 2))
  end

  it "draws the published outline" do
    expect(attribute_of("//g[@class='taskWrapper']//path", "d"))
      .to eq(card.outline)
  end

  it "draws the published rule" do
    rule = attribute_of("//g[@class='taskWrapper']//line", "x2").to_f

    expect(rule).to eq(card.rule.x2)
  end

  it "draws the first line at the published anchor" do
    text = REXML::XPath.first(doc, "//g[@class='eventWrapper']//text")

    expect([text.attributes["x"].to_f, text.attributes["y"].to_f])
      .to eq([cards_of(scene, "event").first.text_x,
              cards_of(scene, "event").first.text_y])
  end

  it "draws later lines at the published baselines" do
    tspans = REXML::XPath.match(doc, "//tspan")

    expect(tspans).not_to be_empty

    expect(tspans.filter_map { |run| run.attributes["y"]&.to_f })
      .to eq(scene.cards.flat_map(&:next_baselines))
  end

  it "steps published baselines 17.6 apart" do
    event = scene.cards.find { |each| each.next_baselines.any? }
    rows = [event.text_y, *event.next_baselines]

    expect(rows.each_cons(2).map { |a, b| (b - a).round(4) }.uniq)
      .to eq([17.6])
  end

  it "emits no translate anywhere" do
    expect(REXML::XPath.match(doc, "//*[@transform]")).to be_empty
  end
end
