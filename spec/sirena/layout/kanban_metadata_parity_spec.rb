# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Layout::Kanban, :aggregate_failures do
  def scene_for(case_id)
    source = File.read("spec/mermaid/kanban/#{case_id}.mmd")
    diagram = Sirena::Parser::Kanban.new.parse(source)
    Sirena::Layout::Kanban.new.call(diagram)
  end

  it "draws priorities as fixed-height card-edge accents" do
    expect(priority_geometry).to eq(
      heights: [44], colors: expected_priority_colors, metadata: [],
    )
  end

  it "places ticket and assignee values together below a wrapped label" do
    card = scene_for("kanban_spec-e33c6002").cards.fetch(0)

    expect(card.background.height).to eq(80)
    expect(card.metadata.map(&:text)).to eq(%w[MC-2037 knsv])
    expect(card.metadata.map(&:y).uniq.length).to eq(1)
    expect(card.accent.color).to eq("lightblue")
  end

  it "renders the priority accent without metadata key labels" do
    expect(rendered_metadata).to eq(
      accent: true, values: %w[MC-2037 knsv], forbidden: [],
    )
  end

  def priority_geometry
    cards = scene_for("kanban_spec-5bba2c43").cards
    { heights: cards.map { |card| card.background.height }.uniq,
      colors: cards.to_h { |card| [card.id, card.accent&.color] },
      metadata: cards.flat_map(&:metadata) }
  end

  def expected_priority_colors
    { "vh" => "red", "h" => "orange", "m" => nil,
      "l" => "blue", "vl" => "lightblue" }
  end

  def rendered_metadata
    source = File.read("spec/mermaid/kanban/kanban_spec-e33c6002.mmd")
    document = REXML::Document.new(Sirena.render(source))
    texts = REXML::XPath.match(document, "//text").map(&:text)
    { accent: !REXML::XPath.first(
      document, "//line[@stroke='lightblue']"
    ).nil?, values: texts & %w[MC-2037 knsv],
      forbidden: texts & ["Priority:", "Ticket:", "Assigned:"] }
  end
end
