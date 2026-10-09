# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/git_graph"
require "sirena/layout/git_graph"
require "sirena/renderer/git_graph"

RSpec.describe Sirena::Renderer::GitGraph do
  subject(:renderer) { described_class.new }

  def scene_for(source)
    diagram = Sirena::Parser::GitGraph.new.parse(source)
    Sirena::Layout::GitGraph.new.call(diagram)
  end

  let(:source) do
    <<~MERMAID
      gitGraph TB:
        commit id: "c1" tag: "v1"
        branch develop
        checkout develop
        commit id: "c2" type: HIGHLIGHT
        checkout main
        merge develop
    MERMAID
  end
  let(:scene) { scene_for(source) }

  it "returns typed final canvas geometry" do
    expect(scene).to be_a(Sirena::Layout::GitGraph::Scene)
    expect(scene.commits).to all(be_a(Sirena::Layout::GitGraph::Commit))
    expect(scene.connections).to all(be_a(Sirena::Layout::GitGraph::Connection))
    expect(scene.view_box).to eq("0 0 #{scene.width} #{scene.height}")
  end

  it "includes framing in commits, connections, and every label" do
    coordinates = scene.commits.flat_map { |commit| [commit.x, commit.y] }
    coordinates.concat(scene.connections.flat_map do |connection|
      [connection.from_x, connection.from_y, connection.to_x, connection.to_y]
    end)
    coordinates.concat(scene.commits.flat_map do |commit|
      commit.labels.flat_map { |label| [label.x, label.y] }
    end)
    coordinates.concat(scene.branches.filter_map do |branch|
      [branch.label.x, branch.label.y] if branch.label
    end.flatten)

    expect(coordinates).to all(be >= 0)
  end

  it "renders commit circles, merge links, and labels" do
    svg = renderer.render(scene)

    expect(svg.children.grep(Sirena::Svg::Circle).length).to eq(scene.commits.length)
    merge = svg.children.grep(Sirena::Svg::Path).find do |path|
      path.stroke_dasharray == "5,3"
    end
    expect(merge).not_to be_nil
    expect(svg.children.grep(Sirena::Svg::Text)).not_to be_empty
  end

  it "renders cherry-pick links as dotted paths" do
    cherry = scene_for(<<~MERMAID)
      gitGraph
        commit id: "c1"
        branch develop
        checkout develop
        commit id: "c2"
        checkout main
        cherry-pick id: "c2"
    MERMAID

    paths = renderer.render(cherry).children.grep(Sirena::Svg::Path)
    expect(paths.map(&:stroke_dasharray)).to include("2,4")
  end

  it "uses Scene canvas dimensions verbatim" do
    svg = renderer.render(scene)

    expect([svg.width, svg.height, svg.view_box])
      .to eq([scene.width, scene.height, scene.view_box])
  end
end
