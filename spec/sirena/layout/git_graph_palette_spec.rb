# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/git_graph"
require "sirena/layout/git_graph"

RSpec.describe Sirena::Layout::GitGraph do
  let(:source) do
    <<~MERMAID
      gitGraph
        commit id: "m"
        branch alpha
        checkout alpha
        commit id: "a"
        checkout main
        commit id: "n"
    MERMAID
  end
  let(:branch_source) do
    lines = ["gitGraph", "  commit id: \"root\""]
    10.times do |index|
      name = "branch#{index}"
      lines.push("  branch #{name}", "  checkout #{name}",
                 "  commit id: \"c#{index}\"", "  checkout main")
    end
    lines.join("\n")
  end
  let(:palette) { %w[#110000 #001100 #000011] }
  let(:theme) do
    Sirena::Theme.new(
      name: "branch colours", colors: { git_graph_palette: palette },
    )
  end
  let(:partial_theme) do
    Sirena::Theme.new(name: "mine", colors: { background: "#101010" })
  end

  def geometry_for(theme = nil)
    diagram = Sirena::Parser::GitGraph.new.parse(source)
    scene = described_class.new.call(diagram, theme: theme)
    [scene.width, scene.height, commit_geometry(scene), branch_geometry(scene)]
  end

  def commit_geometry(scene)
    scene.commits.map do |commit|
      [commit.id, commit.branch, commit.lane, commit.x, commit.y]
    end
  end

  def branch_geometry(scene)
    scene.branches.map do |branch|
      label = branch.label
      [branch.name, branch.lane, label.x, label.y, label.font_size]
    end
  end

  it "takes every branch colour from the wrapping theme palette" do
    diagram = Sirena::Parser::GitGraph.new.parse(branch_source)
    colours = described_class.new.call(diagram, theme: theme)
      .branches.map(&:color)

    expect(colours).to eq(Array.new(11) { |index| palette[index % 3] })
  end

  it "preserves graph geometry under a partial colour theme" do
    expect(geometry_for(partial_theme)).to eq(geometry_for)
  end
end
