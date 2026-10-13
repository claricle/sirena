# frozen_string_literal: true

require "spec_helper"
require "yaml"

module TypedArchitectureSpecHelpers
  module_function

  def points(edge)
    section = edge.sections.first
    [section.start_point, *section.bend_points, section.end_point]
  end

  def segment_crosses?(node, first, last)
    (0..200).any? do |index|
      ratio = index / 200.0
      inside?(node, interpolate(first.x, last.x, ratio),
              interpolate(first.y, last.y, ratio))
    end
  end

  def interpolate(from, to, ratio)
    from + ((to - from) * ratio)
  end

  def inside?(node, x_coord, y_coord)
    x_coord > node.x && x_coord < node.x + node.width &&
      y_coord > node.y && y_coord < node.y + node.height
  end

  def crossings(scene)
    nodes = scene.children.reject { |node| node.kind == "group" }
    scene.edges.flat_map { |edge| edge_crossings(edge, nodes) }
  end

  def edge_crossings(edge, nodes)
    ends = [edge.source, edge.target]
    candidates = nodes.reject { |node| ends.include?(node.id) }
    points(edge).each_cons(2).flat_map do |first, last|
      candidates.select { |node| segment_crosses?(node, first, last) }
    end
  end

  def verdicts
    @verdicts ||= YAML.load_file(
      File.expand_path("../../mermaid/corpus-verdicts.yml", __dir__),
    ).to_h { |row| [row["case"], row["verdict"]] }
  end
end

RSpec.describe Sirena::Renderer::Architecture, :aggregate_failures do
  subject(:renderer) { described_class.new }

  let(:source) { File.read("examples/architecture/01-basic-services.mmd") }
  let(:diagram) { Sirena::Parser::Architecture.new.parse(source) }
  let(:scene) { Sirena::Layout::Architecture.new.call(diagram) }
  let(:svg) { renderer.render(scene) }

  it "renders a typed Document from a typed Scene" do
    expect(svg).to be_a(Sirena::Svg::Document)
    expect(scene).to be_a(Sirena::Layout::Architecture::Scene)
  end

  it "renders typed services and routed edges" do
    expect(svg.to_xml).to include('id="service-frontend"',
                                  'id="edge-frontend-backend"')
  end

  it "renders service labels" do
    expect(svg.to_xml).to include("Frontend", "Backend API", "Database",
                                  "Cache")
  end

  it "renders edge paths" do
    expect(svg.to_xml).to include("<path")
  end

  it "uses the Scene canvas" do
    expect([svg.width, svg.height, svg.view_box])
      .to eq([scene.width, scene.height, scene.view_box])
  end

  describe "an edge label" do
    let(:labeled_scene) do
      diagram = Sirena::Diagram::Architecture.new(
        services: [
          Sirena::Diagram::Architecture::Service.new(id: "a", label: "A",
                                                     icon: "server"),
          Sirena::Diagram::Architecture::Service.new(id: "b", label: "B",
                                                     icon: "server"),
        ],
        groups: [], junctions: [],
        edges: [Sirena::Diagram::Architecture::Edge.new(
          from_id: "a", to_id: "b", from_position: "R", to_position: "L",
          label: "HTTP"
        )]
      )
      Sirena::Layout::Architecture.new.call(diagram)
    end

    it "is positioned by the typed Scene" do
      expect(labeled_scene.edges.first.labels.first.text).to eq("HTTP")
    end

    it "renders the label text" do
      expect(renderer.render(labeled_scene).to_xml).to include(">HTTP<")
    end
  end

  describe "group boundaries and junction circles from typed nodes" do
    let(:group_xml) do
      diagram = Sirena::Diagram::Architecture.new(
        services: [],
        junctions: [Sirena::Diagram::Architecture::Junction.new(
          id: "mid", group_id: "api",
        )],
        groups: [Sirena::Diagram::Architecture::Group.new(
          id: "api", label: "API", icon: "cloud",
        )],
        edges: [],
      )
      scene = Sirena::Layout::Architecture.new.call(diagram)
      renderer.render(scene).to_xml
    end

    it "renders the group boundary, the junction and the group label" do
      expect(group_xml).to include('id="group-api"', 'id="junction-mid"',
                                   "API")
    end

    it "renders the junction circle" do
      expect(group_xml).to include("<circle")
    end
  end

  describe "a junction circle from Scene centre and radius" do
    let(:junction_xml) do
      junction = Sirena::Layout::Architecture::Node.new(
        id: "mid", kind: "junction", x: 300, y: 40, width: 20, height: 12,
        center_x: 310, center_y: 46, radius: 10
      )
      manual_scene = Sirena::Layout::Architecture::Scene.new(
        width: 400, height: 200, view_box: "0 0 400 200",
        children: [junction], edges: []
      )
      renderer.render(manual_scene).to_xml
    end

    it "draws the circle at the Scene centre with the Scene radius" do
      expect(junction_xml).to include('id="junction-mid"', 'cx="310.0"',
                                      'cy="46.0"', 'r="10.0"')
    end

    it "draws no service shape or default radius" do
      expect(junction_xml).not_to include('id="service-mid"', 'r="6.0"')
    end
  end

  it "keeps every routed point inside the Scene canvas" do
    scene.edges.flat_map { |edge| TypedArchitectureSpecHelpers.points(edge) }
      .each do |point|
        expect(point.x).to be_between(0, scene.width)
        expect(point.y).to be_between(0, scene.height)
      end
  end

  context "with every architecture corpus case" do
    paths = Dir.glob(File.expand_path("../../mermaid/architecture/*.mmd",
                                      __dir__))

    paths.each do |path|
      parseable = begin
        Sirena::Parser::Architecture.new.parse(File.read(path))
        true
      rescue Sirena::Parser::ParseError
        false
      end
      unless parseable
        it "refuses #{File.basename(path)} cleanly" do
          case_name = "architecture/#{File.basename(path)}"
          expect(TypedArchitectureSpecHelpers.verdicts.fetch(case_name))
            .to eq("invalid")
          expect { Sirena::Parser::Architecture.new.parse(File.read(path)) }
            .to raise_error(Sirena::Parser::ParseError)
        end
      end
      if parseable
        it "routes #{File.basename(path)} around non-endpoint nodes" do
          diagram = Sirena::Parser::Architecture.new.parse(File.read(path))
          scene = Sirena::Layout::Architecture.new.call(diagram)

          expect(TypedArchitectureSpecHelpers.crossings(scene)).to be_empty
        end
      end
    end
  end
end
