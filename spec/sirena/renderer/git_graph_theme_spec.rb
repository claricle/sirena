# frozen_string_literal: true

require "digest"
require "spec_helper"
require "sirena/renderer/git_graph"

RSpec.describe Sirena::Renderer::GitGraph do
  subject(:svg) { described_class.new(theme: theme).render(scene) }

  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:scene) do
    label = Sirena::Layout::GitGraph::Label
    commit = Sirena::Layout::GitGraph::Commit
    branch = Sirena::Layout::GitGraph::Branch
    connection = Sirena::Layout::GitGraph::Connection
    labels = [
      label.new(
        text: "c1", x: 20, y: 20, text_anchor: "middle", kind: "id",
        font_size: 12
      ),
      label.new(
        text: "v1", x: 20, y: 5, text_anchor: "middle", kind: "tag",
        font_size: 12
      ),
    ]
    commits = [
      commit.new(
        id: "c1", x: 20, y: 30, branch: "main", type: "NORMAL",
        labels: labels
      ),
      commit.new(
        id: "c2", x: 70, y: 30, branch: "main", type: "HIGHLIGHT",
      ),
      commit.new(
        id: "c3", x: 120, y: 30, branch: "main", type: "REVERSE",
      ),
    ]
    branch_label = label.new(
      text: "main", x: 20, y: 55, text_anchor: "middle", kind: "branch",
      font_size: 12
    )
    branches = [branch.new(name: "main", label: branch_label)]
    connections = [
      connection.new(
        from_x: 20, from_y: 30, to_x: 70, to_y: 30,
        from_branch: "main", to_branch: "main", type: :normal
      ),
      connection.new(
        from_x: 70, from_y: 30, to_x: 120, to_y: 30,
        from_branch: "main", to_branch: "main", type: :cherry_pick,
        path: "M70,30 L120,30"
      ),
    ]
    Sirena::Layout::GitGraph::Scene.new(
      width: 160, height: 80, view_box: "0 0 160 80", commits: commits,
      branches: branches, connections: connections
    )
  end
  let(:paint_summary) do
    connections = svg.children.grep(Sirena::Svg::Line) +
      svg.children.grep(Sirena::Svg::Path)
    commits = svg.children.grep(Sirena::Svg::Circle)
    labels = svg.children.grep(Sirena::Svg::Text).to_h do |text|
      [Array(text.content).join, [text.fill, text.font_family]]
    end
    {
      edge_strokes: connections.map(&:stroke),
      commit_paint: commits.map { |item| [item.fill, item.stroke] },
      labels: labels,
    }
  end
  let(:expected_summary) do
    colors = theme.colors
    font = theme.typography&.font_family || "Arial, sans-serif"
    {
      edge_strokes: Array.new(2, colors.edge_stroke),
      commit_paint: [
        [colors.primary, colors.primary],
        [colors.highlight, colors.primary],
        [colors.background, colors.primary],
      ],
      labels: {
        "c1" => [colors.label_text, font],
        "v1" => [colors.accent, font],
        "main" => [colors.primary, font],
      },
    }
  end

  it "uses every default semantic paint role" do
    expect(paint_summary).to eq(expected_summary)
  end

  it "preserves the default SVG bytes" do
    expect(Digest::SHA256.hexdigest(svg.to_xml))
      .to eq("7330e440c404949dd0d81893548894c2fd525a02e135394fd51085f8ddcafecb")
  end

  %i[light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "uses every semantic paint role" do
        expect(paint_summary).to eq(expected_summary)
      end
    end
  end

  context "with a partial theme" do
    let(:theme) do
      Sirena::Theme.new(
        colors: Sirena::Theme::ColorPalette.new(primary: "#123abc"),
      )
    end

    it "leaves absent roles unpainted without legacy hex values" do
      expect(paint_summary).to eq(expected_summary)
    end
  end

  context "with an explicit branch colour" do
    let(:theme) { Sirena::Theme::Registry.get(:dark) }

    before { scene.branches.first.color = "#123456" }

    it "keeps the branch colour ahead of semantic roles" do
      expect(
        [paint_summary[:edge_strokes].first,
         *paint_summary[:commit_paint].first,
         paint_summary[:labels].fetch("main").first],
      ).to eq(Array.new(4, "#123456"))
    end
  end
end
