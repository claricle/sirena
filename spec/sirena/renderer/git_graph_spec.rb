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
  let(:cherry_source) do
    <<~MERMAID
      gitGraph
        commit id: "c1"
        branch develop
        checkout develop
        commit id: "c2"
        checkout main
        cherry-pick id: "c2"
    MERMAID
  end

  def scene_types
    [
      scene.class,
      scene.commits.map(&:class).uniq,
      scene.connections.map(&:class).uniq,
      scene.view_box,
    ]
  end

  def expected_scene_types
    [
      Sirena::Layout::GitGraph::Scene,
      [Sirena::Layout::GitGraph::Commit],
      [Sirena::Layout::GitGraph::Connection],
      "0 0 #{scene.width} #{scene.height}",
    ]
  end

  def coordinates
    commit_coordinates + connection_coordinates + label_coordinates
  end

  def commit_coordinates
    scene.commits.flat_map { |commit| [commit.x, commit.y] }
  end

  def connection_coordinates
    scene.connections.flat_map do |connection|
      [connection.from_x, connection.from_y, connection.to_x, connection.to_y]
    end
  end

  def label_coordinates
    scene.commits.flat_map do |commit|
      commit.labels.flat_map { |label| [label.x, label.y] }
    end + branch_label_coordinates
  end

  def branch_label_coordinates
    scene.branches.filter_map do |branch|
      [branch.label.x, branch.label.y] if branch.label
    end.flatten
  end

  def render_summary
    svg = renderer.render(scene)
    merge = svg.children.grep(Sirena::Svg::Path).find do |path|
      path.stroke_dasharray == "5,3"
    end
    [
      svg.children.grep(Sirena::Svg::Circle).length,
      merge.nil?, svg.children.grep(Sirena::Svg::Text).empty?
    ]
  end

  it "returns typed final canvas geometry" do
    expect(scene_types).to eq(expected_scene_types)
  end

  it "includes framing in commits, connections, and every label" do
    expect(coordinates).to all(be >= 0)
  end

  it "renders commit circles, merge links, and labels" do
    expect(render_summary).to eq([scene.commits.length, false, false])
  end

  it "renders cherry-pick links as dotted paths" do
    paths = renderer.render(scene_for(cherry_source))
      .children.grep(Sirena::Svg::Path)
    expect(paths.map(&:stroke_dasharray)).to include("2,4")
  end

  it "uses Scene canvas dimensions verbatim" do
    svg = renderer.render(scene)

    expect([svg.width, svg.height, svg.view_box])
      .to eq([scene.width, scene.height, scene.view_box])
  end
end
