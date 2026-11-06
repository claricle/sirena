# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph_helpers"

# The line weights and corner radii PlantUML 1.2026.6 draws for deployment,
# use case, entity and group shapes, measured from its SVG: every leaf is a
# hairline, a package and a folder are heavy and black, and every other
# group keeps the plain line.
RSpec.describe Sirena::Notation::PlantUML::NodeGraph::Shapes do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def drawn(body)
    tags = %w[rect ellipse path polygon line circle]
    svg_root(render(body)).get_elements("//*").select do |node|
      tags.include?(node.name)
    end
  end

  def looks(nodes)
    nodes.map { |n| [n.attributes["stroke-width"], n.attributes["stroke"]] }
  end

  def shapes_of(body, tag)
    REXML::XPath.match(svg_root(render(body)), "//#{tag}")
  end

  %w[node file cloud database folder frame artifact].each do |kind|
    it "draws a leaf #{kind} with a 0.5 hairline" do
      expect(looks(drawn("#{kind} K1")).map(&:first).uniq).to eq(["0.5"])
    end
  end

  it "draws a use case ellipse and an actor with a 0.5 hairline" do
    expect(looks(drawn("actor A1\nusecase U1")).map(&:first).uniq)
      .to eq(["0.5"])
  end

  it "rounds the corners of a plain box by 2.5" do
    expect(shapes_of("rectangle R1", "rect").map { |r| r.attributes["rx"] })
      .to eq(["2.5"])
  end

  {
    "package" => ["1.5", "#000000"], "folder" => ["1.5", "#000000"],
    "node" => ["1", "#181818"], "cloud" => ["1", "#181818"],
    "database" => ["1", "#181818"], "frame" => ["1", "#181818"],
    "rectangle" => ["1", "#181818"]
  }.each do |kind, (width, colour)|
    it "draws a #{kind} group with #{width} in #{colour}" do
      group = drawn("#{kind} \"G\" {\n  [c]\n}").select do |n|
        n.attributes["fill"] == "none" || n.name == "polygon"
      end
      expect(looks(group).uniq).to eq([[width, colour]])
    end
  end

  describe "an entity" do
    let(:body) do
      "entity \"User\" as u {\n  *id : number\n  --\n  name : text\n}"
    end

    it "draws its frame as a rounded 0.5 hairline" do
      frame = shapes_of(body, "rect").first.attributes
      expect([frame["stroke-width"], frame["rx"], frame["ry"]])
        .to eq(["0.5", "2.5", "2.5"])
    end

    it "keeps the spot and the bullet at 1 and the rules at 0.5 then 1" do
      lines = shapes_of(body, "line").map { |l| l.attributes["stroke-width"] }
      circles = shapes_of(body, "circle").map do |c|
        c.attributes["stroke-width"]
      end
      expect([lines, circles]).to eq([%w[0.5 1], %w[1 1]])
    end
  end
end
