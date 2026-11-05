# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph_helpers"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::Layout do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:doc) { REXML::Document.new(render_fixture("plantuml-lrg-2-8")) }
  let(:curves) do
    REXML::XPath.match(doc, "//path").map { |p| p.attributes["d"] }
      .select { |d| d.scan("C").size > 1 }
  end

  def xs(polygon)
    polygon.attributes["points"].split.map { |p| p.split(",")[0].to_f }
  end

  def holds?(polygon, text)
    ys = polygon.attributes["points"].split.map { |p| p.split(",")[1].to_f }
    polygon.attributes["fill"] == "#FEFFDD" &&
      text.attributes["y"].to_f.between?(*ys.minmax)
  end

  # [left, right] of the note joined to several objects
  def note
    text = REXML::XPath.match(doc, "//text")
      .find { |t| t.text == "This note is connected" }
    xs(REXML::XPath.match(doc, "//polygon").find { |g| holds?(g, text) }).minmax
  end

  # the point the first piece of a curve ends at
  def bend(path)
    path.split(" C ")[1].split.last(2).map(&:to_f)
  end

  it "bends a link through the rank it skips, on each side of a note",
     :aggregate_failures do
    bends = curves.map { |d| bend(d)[0] }

    expect(curves.size).to eq(2)
    expect(bends.min).to be < note[0]
    expect(bends.max).to be > note[1]
  end
end
