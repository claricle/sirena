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
      x_coord = first.x + ((last.x - first.x) * ratio)
      y_coord = first.y + ((last.y - first.y) * ratio)
      x_coord > node.x && x_coord < node.x + node.width &&
        y_coord > node.y && y_coord < node.y + node.height
    end
  end

  def verdicts
    @verdicts ||= YAML.load_file(
      File.expand_path("../../mermaid/corpus-verdicts.yml", __dir__),
    ).to_h { |row| [row["case"], row["verdict"]] }
  end
end

RSpec.describe Sirena::Renderer::Architecture do
  subject(:renderer) { described_class.new }

  let(:source) { File.read("examples/architecture/01-basic-services.mmd") }
  let(:diagram) { Sirena::Parser::Architecture.new.parse(source) }
  let(:scene) { Sirena::Layout::Architecture.new.call(diagram) }
  let(:svg) { renderer.render(scene) }

  it "renders typed services, routed edges, labels, and the Scene canvas" do
    xml = svg.to_xml
    expect(svg).to be_a(Sirena::Svg::Document)
    expect(scene).to be_a(Sirena::Layout::Architecture::Scene)
    expect(xml).to include('id="service-frontend"',
                           'id="edge-frontend-backend"')
    expect(xml).to include("Frontend", "Backend API", "Database", "Cache")
    expect(xml).to include("<path")
    expect([svg.width, svg.height, svg.view_box])
      .to eq([scene.width, scene.height, scene.view_box])
  end

  it "renders an edge label positioned by the typed Scene" do
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
    labeled_scene = Sirena::Layout::Architecture.new.call(diagram)

    expect(labeled_scene.edges.first.labels.first.text).to eq("HTTP")
    expect(renderer.render(labeled_scene).to_xml).to include(">HTTP<")
  end

  it "renders group boundaries and junction circles from typed nodes" do
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
    xml = renderer.render(Sirena::Layout::Architecture.new.call(diagram)).to_xml
    expect(xml).to include('id="group-api"', 'id="junction-mid"', "API")
    expect(xml).to include("<circle")
  end

  it "centers a junction circle and derives its radius from width" do
    junction = Sirena::Layout::Architecture::Node.new(
      id: "mid", kind: "junction", x: 300, y: 40, width: 20, height: 12,
    )
    manual_scene = Sirena::Layout::Architecture::Scene.new(
      width: 400, height: 200, view_box: "0 0 400 200",
      children: [junction], edges: []
    )
    xml = renderer.render(manual_scene).to_xml

    expect(xml).to include('id="junction-mid"', 'cx="310.0"', 'cy="46.0"',
                           'r="10.0"')
    expect(xml).not_to include('id="service-mid"', 'r="6.0"')
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
          nodes = scene.children.reject { |node| node.kind == "group" }
          scene.edges.each do |edge|
            candidates = nodes.reject do |node|
              [edge.source, edge.target].include?(node.id)
            end
            TypedArchitectureSpecHelpers.points(edge).each_cons(2) do |first, last|
              candidates.each do |node|
                expect(TypedArchitectureSpecHelpers.segment_crosses?(node,
                                                                     first, last))
                  .to be(false)
              end
            end
          end
        end
      end
    end
  end
end
