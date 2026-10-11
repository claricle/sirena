# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe "Kanban metadata parity" do
  def scene_for(case_id)
    source = File.read("spec/mermaid/kanban/#{case_id}.mmd")
    diagram = Sirena::Parser::Kanban.new.parse(source)
    Sirena::Layout::Kanban.new.call(diagram)
  end

  it "draws priorities as fixed-height card-edge accents" do
    scene = scene_for("kanban_spec-5bba2c43")
    cards = scene.cards.to_h { |card| [card.id, card] }

    expect(cards.values.map { |card| card.background.height }.uniq).to eq([44])
    expect(cards.transform_values { |card| card.accent&.color }).to eq(
      "vh" => "red", "h" => "orange", "m" => nil,
      "l" => "blue", "vl" => "lightblue",
    )
    expect(cards.values.flat_map(&:metadata)).to be_empty
  end

  it "places ticket and assignee values together below a wrapped label" do
    card = scene_for("kanban_spec-e33c6002").cards.fetch(0)

    expect(card.background.height).to eq(86)
    expect(card.metadata.map(&:text)).to eq(%w[MC-2037 knsv])
    expect(card.metadata.map(&:y).uniq.length).to eq(1)
    expect(card.accent.color).to eq("lightblue")
  end

  it "renders the priority accent without metadata key labels" do
    source = File.read("spec/mermaid/kanban/kanban_spec-e33c6002.mmd")
    xml = Sirena.render(source)
    document = REXML::Document.new(xml)

    expect(REXML::XPath.first(document, "//line[@stroke='lightblue']"))
      .not_to be_nil
    texts = REXML::XPath.match(document, "//text").map(&:text)
    expect(texts).to include("MC-2037", "knsv")
    expect(texts).not_to include("Priority:", "Ticket:", "Assigned:")
  end
end
