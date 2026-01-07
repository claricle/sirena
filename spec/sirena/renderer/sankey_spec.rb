# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/sankey"
require "sirena/transform/sankey"
require "sirena/parser/sankey"

RSpec.describe Sirena::Renderer::SankeyRenderer do
  let(:renderer) { described_class.new }
  let(:parser) { Sirena::Parser::SankeyParser.new }
  let(:transform) { Sirena::Transform::SankeyTransform.new }

  describe "#render" do
    it "renders a simple sankey diagram" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
        B,C,20
      SANKEY

      diagram = parser.parse(source)
      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to be > 0
      expect(svg.height).to be > 0
    end

    it "renders sankey with node labels" do
      source = <<~SANKEY
        sankey-beta
        Source [Energy Source]
        Process [Processing Plant]
        Output [Useful Energy]
        Source,Process,100
        Process,Output,70
      SANKEY

      diagram = parser.parse(source)
      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      xml = svg.to_xml
      expect(xml).to include("Energy Source")
      expect(xml).to include("Processing Plant")
    end

    it "renders flows with proper width" do
      source = <<~SANKEY
        sankey-beta
        A,B,100
        A,C,50
      SANKEY

      diagram = parser.parse(source)
      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      # Flow widths should be proportional to values
      expect(graph[:flows][0][:width]).to be > graph[:flows][1][:width]
    end

    it "includes title in rendered output" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
      SANKEY

      diagram = parser.parse(source)
      diagram.title = "Energy Flow"
      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      xml = svg.to_xml
      expect(xml).to include("Energy Flow")
    end

    it "renders multiple flows" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
        B,C,7
        B,D,3
      SANKEY

      diagram = parser.parse(source)
      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(graph[:flows].length).to eq(3)
    end

    it "handles complex flow networks" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
        A,C,5
        B,D,8
        C,D,3
      SANKEY

      diagram = parser.parse(source)
      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(graph[:nodes].length).to eq(4)
      expect(graph[:flows].length).to eq(4)
    end
  end
end