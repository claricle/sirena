# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph/node_graph_helpers"

# Port and container labels at the size of the PlantUML JAR (14 px) and links
# that bend round the boxes between their ends, as the JAR draws splines.
RSpec.describe Sirena::Notation::PlantUML::NodeGraph do
  include NodeGraphHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def texts(svg)
    REXML::XPath.match(svg_root(svg), "//text")
      .to_h { |node| [node.text, node.attributes] }
  end

  def rects(svg)
    REXML::XPath.match(svg_root(svg), "//rect").map(&:attributes)
  end

  describe "labels" do
    let(:svg) do
      render("component C {\n portin p1\n portout po1\n component c1\n}")
    end

    it "sets node text at 14 px" do
      expect(texts(svg)["c1"]["font-size"]).to eq("14")
    end

    it "centres the title of a component container at the top, in bold" do
      title = texts(svg)["C"]
      expect([title["text-anchor"], title["font-weight"]])
        .to eq(%w[middle bold])
    end

    it "puts an incoming port's label 15 px above its square" do
      square = rects(svg).find { |rect| rect["width"] == "12.0" }
      expect(square["y"].to_f - texts(svg)["p1"]["y"].to_f).to be_within(0.5)
        .of(15.0)
    end

    it "puts an outgoing port's label 25.5 px below the top of its square" do
      square = rects(svg).filter { |rect| rect["width"] == "12.0" }.last
      expect(texts(svg)["po1"]["y"].to_f - square["y"].to_f).to be_within(0.5)
        .of(25.5)
    end

    it "sizes a component as the JAR does: text plus 40 by text plus 30" do
      width = Sirena::TextMeasurement.measure("c1", font_size: 14)[:width]
      box = rects(svg).find { |rect| rect["rx"] == "2.5" }
      expect(box["width"].to_f).to be_within(0.1).of(width + 40)
    end
  end

  describe "a link past a box in its way" do
    let(:crossing) { "[a] --> [b]\n[b] --> [c]\n[a] --> [c]" }
    let(:paths) { REXML::XPath.match(svg_root(render(crossing)), "//path") }

    it "curves through a bend beside the box" do
      curve = paths.find { |path| path.attributes["d"].include?(" C ") }
      expect(curve.attributes["fill"]).to eq("none")
    end

    it "ends the arrowhead along the curve, not along the chord" do
      svg = render(crossing)
      curve = REXML::XPath.match(svg_root(svg), "//path").first
      tips = REXML::XPath.match(svg_root(svg), "//polygon")
        .map { |poly| poly.attributes["points"].split.first }
      expect(tips).to include(curve.attributes["d"].split.last(2).join(","))
    end

    it "leaves a link nothing is in the way of as a straight line" do
      svg = render("[a] --> [b]")
      expect(REXML::XPath.match(svg_root(svg), "//path")).to be_empty
    end

    it "does not detour round what holds an end of the link" do
      svg = render("node N {\n [a]\n [b]\n}\n[a] --> [b]")
      expect(svg).not_to include(" C ")
    end

    it "does not detour round a port on a frame" do
      svg = render("component C {\n portin p1\n component c1\n}\np1 --> c1")
      expect(svg).not_to include(" C ")
    end

    it "bends only links between nodes, not a note pointer" do
      svg = render("[a] --> [b]\n[b] --> [c]\n[a] --> [c]\n" \
                   "note right of [c] : n")
      expect(REXML::XPath.match(svg_root(svg), "//path").size).to eq(1)
    end
  end

  describe described_class::Curve do
    def pt(*pairs) = pairs

    it "draws two points as a line" do
      expect(described_class.path(pt([0.0, 0.0], [10.0, 20.0])))
        .to eq("M 0.0 0.0 L 10.0 20.0")
    end

    it "draws a smooth cubic through each bend" do
      d = described_class.path(pt([0.0, 0.0], [20.0, 40.0], [0.0, 80.0]))
      expect(d.scan("C").size).to eq(2)
    end

    it "drops a bend that is too close to its neighbours" do
      d = described_class.path(pt([0.0, 0.0], [1.0, 1.0], [0.0, 80.0]))
      expect(d).to eq("M 0.0 0.0 L 0.0 80.0")
    end

    it "drops a bend that is too close to the end" do
      d = described_class.path(pt([0.0, 0.0], [0.0, 40.0], [1.0, 41.0]))
      expect(d).to eq("M 0.0 0.0 L 1.0 41.0")
    end
  end
end
