# frozen_string_literal: true

require "spec_helper"
require "digest"
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
  let(:render_digests) do
    partial = { name: "mine", colors: { background: "#101010" } }
    [Sirena.render(source), Sirena.render(source, theme: partial)].map do |svg|
      Digest::SHA256.hexdigest(svg)
    end
  end

  it "takes every branch colour from the wrapping theme palette" do
    diagram = Sirena::Parser::GitGraph.new.parse(branch_source)
    colours = described_class.new.call(diagram, theme: theme)
      .branches.map(&:color)

    expect(colours).to eq(Array.new(11) { |index| palette[index % 3] })
  end

  it "preserves default and partial-theme SVG bytes" do
    expect(render_digests).to eq(
      %w[8ed4e31e0f2bdb4b1623404216f7be7e6d11ee7197149a0b3b8bd94cfb13fc75
         d28127a366e54cf240fba97180f0f8a1f0363fadef6fc65652ca88316ff4fec8],
    )
  end
end
