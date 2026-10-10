# frozen_string_literal: true

require "spec_helper"
require "nokogiri"
require "sirena/parser/git_graph"
require "sirena/layout/git_graph"
require "sirena/renderer/git_graph"

RSpec.describe Sirena::Layout::GitGraph do
  let(:source) do
    <<~MERMAID
      gitGraph:
        commit id: "main-1"
        branch feature
        checkout feature
        commit id: "feature-1"
        checkout main
        commit id: "main-2"
    MERMAID
  end
  let(:diagram) { Sirena::Parser::GitGraph.new.parse(source) }
  let(:scene) { described_class.new.call(diagram) }
  let(:first_commit_x_by_branch) do
    scene.commits.group_by(&:branch)
      .transform_values { |commits| commits.first.x }
  end
  let(:branch_label_offsets) do
    scene.branches.to_h do |branch|
      first_commit_x = first_commit_x_by_branch.fetch(branch.name)
      [branch.name, branch.label.x - first_commit_x]
    end
  end

  it "uses one zero-based lane per semantic branch" do
    metadata = scene.branches.map { |branch| [branch.name, branch.lane] }

    expect(metadata).to eq([["main", 0], ["feature", 1]])
  end

  it "matches Mermaid commit and lane spacing" do
    time_steps = scene.commits.each_cons(2)
      .map { |left, right| right.x - left.x }
    lane_step = scene.commits[1].y - scene.commits[0].y

    expect([time_steps, lane_step]).to eq([[50.0, 50.0], 90.0])
  end

  it "anchors horizontal branch labels to the first commit in each lane" do
    expect(branch_label_offsets).to eq("main" => 15.0, "feature" => 15.0)
  end

  it "renders Mermaid-sized commit markers" do
    svg = Sirena::Renderer::GitGraph.new.render(scene).to_xml
    document = Nokogiri::XML(svg)
    radii = document.xpath("//*[local-name()='circle']")
      .map { |node| node["r"].to_f }

    expect(radii).to eq([10.0, 10.0, 10.0])
  end
end
