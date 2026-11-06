# frozen_string_literal: true

require "spec_helper"
require_relative "node_graph_helpers"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::LabelFan do
  let(:edge_class) do
    Struct.new(:label, :pointer, :from_row, :to_row, :ends)
  end
  let(:route_class) do
    Struct.new(:edge, :points, :label_at, keyword_init: true)
  end

  def route(label, points, **options)
    route_class.new(edge: edge_class.new(label, *options.values_at(
      :pointer, :from_row, :to_row, :ends
    )), points: points)
  end

  def fan(first_label, second_label, **options)
    [route(first_label, [[100.0, 0.0], [0.0, 100.0]], **options),
     route(second_label, [[100.0, 0.0], [140.0, 100.0]], **options)]
  end

  describe "#call" do
    it "bends two links whose labels meet through their label points" do
      routes = fan("a long first label", "a long second label")

      described_class.new(1).call(routes)

      expect(routes.map(&:label_at)).to eq([[30.0, 50.0], [128.0, 50.0]])
    end

    it "puts the bent link through its label point" do
      routes = fan("a long first label", "a long second label")

      described_class.new(1).call(routes)

      expect(routes.first.points)
        .to eq([[100.0, 0.0], [30.0, 50.0], [0.0, 100.0]])
    end

    it "leaves links whose labels stand apart straight" do
      routes = fan("a", "b")

      described_class.new(1).call(routes)

      expect(routes.map(&:label_at)).to eq([nil, nil])
    end

    it "leaves links beside each other along the rank axis straight" do
      routes = [route("one long label", [[100.0, 0.0], [0.0, 100.0]]),
                route("one long label", [[100.0, 300.0], [0.0, 400.0]])]

      described_class.new(1).call(routes)

      expect(routes.map(&:label_at)).to eq([nil, nil])
    end

    it "leaves a link with no label alone" do
      routes = fan("a long first label", "")

      described_class.new(1).call(routes)

      expect(routes.map(&:label_at)).to eq([nil, nil])
    end

    it "leaves note pointers and entity links alone" do
      routes = fan("a long first label", "a long second label", pointer: true)

      described_class.new(1).call(routes)

      expect(routes.map(&:label_at)).to eq([nil, nil])
    end

    it "keeps a crowded link that runs straight on its line" do
      routes = [route("a long first label", [[100.0, 0.0], [100.0, 100.0]]),
                route("a long second label", [[100.0, 0.0], [160.0, 100.0]])]

      described_class.new(1).call(routes)

      expect(routes.map(&:label_at)).to eq([nil, [142.0, 50.0]])
    end

    it "bends across a left to right layout" do
      routes = [route("a long first label", [[0.0, 100.0], [100.0, 0.0]]),
                route("a long second label", [[0.0, 100.0], [100.0, 160.0]])]

      described_class.new(0).call(routes)

      expect(routes.map(&:label_at)).to eq([[50.0, 30.0], [50.0, 142.0]])
    end
  end

  describe "in a diagram" do
    include NodeGraphHelpers

    include_context "with an isolated notation registry"

    before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

    let(:svg) do
      render("node foo\nfoo --> bar : [#red,dashed,2]\n" \
             "foo --> qux : [blue,dotted,8]")
    end

    def label_ys
      REXML::XPath.match(svg_root(svg), "//text")
        .select { |text| text.text.start_with?("[") }
        .map { |text| text.attributes["y"].to_f }
    end

    it "draws the links of two crowded labels as splines" do
      curves = REXML::XPath.match(svg_root(svg), "//path")
        .count { |path| path.attributes["d"].scan(" C ").size == 2 }

      expect(curves).to eq(2)
    end

    it "keeps those labels within two lines of each other" do
      expect(label_ys.max - label_ys.min).to be < 28
    end
  end
end
