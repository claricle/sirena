# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/sankey"
require "sirena/layout/sankey"
require "sirena/parser/sankey"

RSpec.describe Sirena::Renderer::Sankey, :aggregate_failures do
  let(:renderer) { described_class.new }
  let(:parser) { Sirena::Parser::Sankey.new }
  let(:layout) { Sirena::Layout::Sankey.new }
  let(:engine) { Sirena::Engine.new }
  let(:two_flow_source) do
    <<~SANKEY
      sankey-beta
      A,B,100
      A,C,50
    SANKEY
  end

  def scene_for(source)
    layout.call(parser.parse(source))
  end

  def final_geometry_evidence
    scene = scene_for(two_flow_source)
    [
      document_evidence(scene),
      node_evidence(scene),
      label_evidence(scene),
      flow_evidence(scene.flows.first),
    ]
  end

  def document_evidence(scene)
    svg = renderer.render(scene)
    [scene.width, scene.height, scene.view_box, svg.view_box]
  end

  def node_evidence(scene)
    scene.nodes.map { |node| [node.id, node.x, node.y] }
  end

  def label_evidence(scene)
    label = scene.nodes.first.label
    [label.x, label.y]
  end

  def flow_evidence(flow)
    [
      flow.source_x,
      flow.source_y,
      flow.target_x,
      flow.target_y,
      flow.path,
    ]
  end

  def expected_final_geometry
    [
      [400.0, 270.0, "0 0 400 270", "0 0 400 270"],
      [["A", 60.0, 100.0], ["B", 210.0, 100.0], ["C", 210.0, 170.0]],
      [77.0, 125.0],
      [95.0, 120.0, 210.0, 120.0, expected_flow_path],
    ]
  end

  def expected_flow_path
    [
      "M 95 95.0",
      "C 152.5 95.0, 152.5 95.0, 210 95.0",
      "L 210 145.0",
      "C 152.5 145.0, 152.5 145.0, 95 145.0",
      "Z",
    ].join(" ")
  end

  def grid_calls
    calls = []
    allow(Sirena::Layout::Grid).to receive(:apply) do |graph|
      calls << graph
      Sirena::Layout::Grid.new.apply(graph)
    end
    calls
  end

  def engine_layout(diagram, layout_class)
    result = engine.send(:transform_diagram, diagram, layout_class, nil,
                         default_theme)
    engine.send(:layout_graph, result)
  end

  def engine_transition_evidence
    calls = grid_calls
    sankey = engine_layout(parser.parse("sankey-beta\nA,B,10\n"),
                           Sirena::Layout::Sankey)
    legacy = engine_layout(instance_double(Sirena::Diagram::Base, valid?: true),
                           SpecSupport::LegacyLayout)
    [calls.length, sankey_position(sankey), legacy_position(legacy)]
  end

  def default_theme
    Sirena::Theme::Registry.get(:default)
  end

  def sankey_position(scene)
    [scene.nodes.first.x, scene.nodes.first.y]
  end

  def legacy_position(graph)
    graph[:children].first.values_at(:x, :y)
  end

  describe "#render" do
    it "renders a simple sankey diagram" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
        B,C,20
      SANKEY

      scene = scene_for(source)
      svg = renderer.render(scene)

      expect(scene).to be_a(Sirena::Layout::Sankey::Scene)
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

      svg = renderer.render(scene_for(source))

      expect(svg).to be_a(Sirena::Svg::Document)
      xml = svg.to_xml
      expect(xml).to include("Energy Source")
      expect(xml).to include("Processing Plant")
    end

    it "renders flows with proper width" do
      scene = scene_for(two_flow_source)

      # Flow widths should be proportional to values
      expect(scene.flows[0].width).to be > scene.flows[1].width
    end

    it "includes title in rendered output" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
      SANKEY

      diagram = parser.parse(source)
      diagram.title = "Energy Flow"
      scene = layout.call(diagram)
      svg = renderer.render(scene)

      xml = svg.to_xml
      expect(scene.title)
        .to have_attributes(text: "Energy Flow", x: 200.0, y: 40.0)
      expect(xml).to include("Energy Flow")
    end

    it "renders multiple flows" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
        B,C,7
        B,D,3
      SANKEY

      scene = scene_for(source)
      svg = renderer.render(scene)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(scene.flows.length).to eq(3)
    end

    it "handles complex flow networks" do
      source = <<~SANKEY
        sankey-beta
        A,B,10
        A,C,5
        B,D,8
        C,D,3
      SANKEY

      scene = scene_for(source)
      svg = renderer.render(scene)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(scene.nodes.length).to eq(4)
      expect(scene.flows.length).to eq(4)
    end

    it "renders the final canvas coordinates without adding an offset" do
      expect(final_geometry_evidence).to eq(expected_final_geometry)
    end

    it "keeps Grid on legacy results and away from the Sankey Scene" do
      expect(engine_transition_evidence)
        .to eq([1, [60.0, 100.0], [50, 50]])
    end
  end
end
