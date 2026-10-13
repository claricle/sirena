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

  def builtin_themes
    %i[default dark].map { |name| Sirena::Theme::Registry.get(name) }
  end

  def branch_colours(theme)
    diagram = Sirena::Parser::GitGraph.new.parse(branch_source)
    described_class.new.call(diagram, theme: theme).branches.map(&:color)
  end

  def palette_colours(theme)
    palette = theme.colors.git_graph_palette
    Array.new(11) { |index| palette[index % palette.length] }
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

  context "with the default and dark theme palettes" do
    it "takes each branch colour from its own theme palette" do
      colours = builtin_themes.map { |builtin| branch_colours(builtin) }
      expected = builtin_themes.map { |builtin| palette_colours(builtin) }

      expect(colours).to eq(expected)
    end

    it "takes distinct branch colours from the two palettes" do
      colours = builtin_themes.map { |builtin| branch_colours(builtin) }

      expect(colours.last).not_to eq(colours.first)
    end
  end

  it "preserves graph geometry under a partial colour theme" do
    expect(geometry_for(partial_theme)).to eq(geometry_for)
  end
end
