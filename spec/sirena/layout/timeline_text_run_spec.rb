# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Layout::TimelineTextRun do
  include TimelineSceneHelpers

  let(:source) do
    "timeline\n section a\n 2020 : Machinery, Water power, Steam <br>power\n"
  end
  let(:scene) { lay_out(source) }
  let(:card) { scene.cards.find { |item| item.lines.length > 1 } }

  def summaries(runs)
    runs.map { |run| [run.content, run.x, run.y] }
  end

  def rendered_summaries
    xml = Sirena::Renderer::Timeline.new.render(scene).to_xml
    REXML::XPath.match(REXML::Document.new(xml), "//tspan").map do |run|
      [run.text, run.attributes["x"].to_f,
       run.attributes["y"]&.to_f]
    end
  end

  it "publishes every wrapped line and its final canvas position" do
    expected = card.lines.each_with_index.map do |content, index|
      [content, card.text_x,
       index.zero? ? nil : card.next_baselines.fetch(index - 1)]
    end

    expect(summaries(card.text_runs)).to eq(expected)
  end

  it "renders only the published typed runs" do
    expected = summaries(card.text_runs)
    card.lines = ["renderer must ignore this legacy text"]
    card.next_baselines = [-100]

    expect(rendered_summaries).to eq(expected)
  end
end
