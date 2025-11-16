# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/git_graph"
require "sirena/transform/git_graph"
require "sirena/renderer/git_graph"

RSpec.describe "Git Graph Integration" do
  let(:parser) { Sirena::Parser::GitGraphParser.new }
  let(:transform) { Sirena::Transform::GitGraph.new }
  let(:renderer) { Sirena::Renderer::GitGraph.new }

  describe "simple linear git graph" do
    let(:source) do
      <<~MERMAID
        gitGraph
          commit id: "Initial"
          commit id: "Second"
          commit id: "Third"
      MERMAID
    end

    it "parses, transforms, and renders successfully" do
      # Parse
      diagram = parser.parse(source)
      expect(diagram).to be_a(Sirena::Diagram::GitGraph)
      expect(diagram.commits.length).to eq(3)

      # Transform
      layout = transform.to_graph(diagram)
      expect(layout[:commits].length).to eq(3)
      expect(layout[:branches].length).to be >= 1

      # Render
      svg = renderer.render(layout)
      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to be > 0
      expect(svg.height).to be > 0
    end

    it "positions commits sequentially" do
      diagram = parser.parse(source)
      layout = transform.to_graph(diagram)

      x_positions = layout[:commits].map { |c| c[:x] }
      expect(x_positions).to eq(x_positions.sort)
    end

    it "assigns all commits to the same lane" do
      diagram = parser.parse(source)
      layout = transform.to_graph(diagram)

      lanes = layout[:commits].map { |c| c[:lane] }.uniq
      # All commits should be on the same lane
      expect(lanes.length).to eq(1)
    end
  end

  describe "git graph with branches" do
    let(:source) do
      <<~MERMAID
        gitGraph
          commit id: "Initial"
          branch develop
          checkout develop
          commit id: "Feature"
          checkout main
          commit id: "Hotfix"
      MERMAID
    end

    it "parses, transforms, and renders successfully" do
      diagram = parser.parse(source)
      expect(diagram.commits.length).to eq(3)
      expect(diagram.branches.length).to be >= 1

      layout = transform.to_graph(diagram)
      expect(layout[:commits].length).to eq(3)
      expect(layout[:branches].length).to be >= 2

      svg = renderer.render(layout)
      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it "assigns different lanes to different branches" do
      diagram = parser.parse(source)
      layout = transform.to_graph(diagram)

      # Find commits on different branches
      main_commits = layout[:commits].select { |c| c[:branch] == "main" }
      develop_commits = layout[:commits].select { |c| c[:branch] == "develop" }

      main_lanes = main_commits.map { |c| c[:lane] }.uniq
      develop_lanes = develop_commits.map { |c| c[:lane] }.uniq

      # Different branches should have different lanes
      expect(main_lanes).not_to eq(develop_lanes)
    end
  end

  describe "git graph with merge" do
    let(:source) do
      <<~MERMAID
        gitGraph
          commit id: "c1"
          branch develop
          checkout develop
          commit id: "c2"
          checkout main
          merge develop
      MERMAID
    end

    it "parses, transforms, and renders successfully" do
      diagram = parser.parse(source)
      layout = transform.to_graph(diagram)
      svg = renderer.render(layout)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it "creates merge connections" do
      diagram = parser.parse(source)
      layout = transform.to_graph(diagram)

      merge_connections = layout[:connections].select do |c|
        c[:type] == :merge
      end

      expect(merge_connections).not_to be_empty
    end

    it "marks merge commits" do
      diagram = parser.parse(source)
      merge_commits = diagram.commits.select(&:is_merge)

      expect(merge_commits).not_to be_empty
    end
  end

  describe "git graph with tags" do
    let(:source) do
      <<~MERMAID
        gitGraph
          commit id: "c1" tag: "v1.0.0"
          commit id: "c2"
          commit id: "c3" tag: "v2.0.0"
      MERMAID
    end

    it "parses and preserves tags" do
      diagram = parser.parse(source)

      tagged_commits = diagram.commits.select { |c| c.tag }
      expect(tagged_commits.length).to eq(2)
      expect(tagged_commits.map(&:tag)).to include("v1.0.0", "v2.0.0")
    end

    it "includes tags in layout" do
      diagram = parser.parse(source)
      layout = transform.to_graph(diagram)

      tagged_commits = layout[:commits].select { |c| c[:tag] }
      expect(tagged_commits.length).to eq(2)
    end
  end

  describe "git graph with commit types" do
    let(:source) do
      <<~MERMAID
        gitGraph
          commit id: "c1"
          commit id: "c2" type: HIGHLIGHT
          commit id: "c3" type: REVERSE
      MERMAID
    end

    it "parses commit types" do
      diagram = parser.parse(source)

      types = diagram.commits.map(&:type)
      expect(types).to include("NORMAL", "HIGHLIGHT", "REVERSE")
    end

    it "preserves commit types in layout" do
      diagram = parser.parse(source)
      layout = transform.to_graph(diagram)

      types = layout[:commits].map { |c| c[:type] }
      expect(types).to include("NORMAL", "HIGHLIGHT", "REVERSE")
    end
  end

  describe "git graph with cherry-pick" do
    let(:source) do
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

    it "parses cherry-pick operations" do
      diagram = parser.parse(source)

      cherry_picked = diagram.commits.select(&:is_cherry_pick)
      expect(cherry_picked).not_to be_empty
    end

    it "creates cherry-pick connections" do
      diagram = parser.parse(source)
      layout = transform.to_graph(diagram)

      cherry_pick_connections = layout[:connections].select do |c|
        c[:type] == :cherry_pick
      end

      expect(cherry_pick_connections).not_to be_empty
    end
  end

  describe "complex git graph" do
    let(:source) do
      <<~MERMAID
        gitGraph
          commit id: "Initial"
          branch develop
          checkout develop
          commit id: "Dev1"
          commit id: "Dev2"
          checkout main
          commit id: "Hotfix" tag: "v1.0.1"
          checkout develop
          commit id: "Dev3"
          checkout main
          merge develop tag: "v2.0.0"
          commit id: "Post-release"
      MERMAID
    end

    it "handles complex branching and merging" do
      diagram = parser.parse(source)
      expect(diagram.commits.length).to be >= 5
      expect(diagram.branches.length).to be >= 1

      layout = transform.to_graph(diagram)
      expect(layout[:commits].length).to be >= 5
      expect(layout[:connections].length).to be >= 4

      svg = renderer.render(layout)
      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to be > 0
      expect(svg.height).to be > 0
    end

    it "creates proper parent-child relationships" do
      diagram = parser.parse(source)
      layout = transform.to_graph(diagram)

      # Each commit except the first should have at least one parent
      commits_with_parents = layout[:commits].select do |c|
        c[:parent_ids].any?
      end

      expect(commits_with_parents.length).to be >= 4
    end

    it "renders all branches with different colors" do
      diagram = parser.parse(source)
      layout = transform.to_graph(diagram)

      colors = layout[:branches].map { |b| b[:color] }.uniq
      expect(colors.length).to eq(layout[:branches].length)
    end
  end
end