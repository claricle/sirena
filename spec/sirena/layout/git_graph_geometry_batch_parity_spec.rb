# frozen_string_literal: true

require "spec_helper"
require "nokogiri"

RSpec.describe Sirena::Layout::GitGraph, :aggregate_failures do
  def scene_for(source)
    diagram = Sirena::Parser::GitGraph.new.parse(source)
    described_class.new.call(diagram)
  end

  it "places generated-ID branch labels at Mermaid's leading boundary" do
    expect(branch_offsets)
      .to eq("main" => -86.172, "feature" => -151.308)
  end

  it "paints bottom-to-top markers in Mermaid's visual order" do
    expect(bottom_to_top_marker_y).to eq([50.0, 100.0, 150.0])
  end

  def branch_offsets
    scene = scene_for(generated_branch_source)
    first_x = scene.commits.group_by(&:branch)
      .transform_values { |commits| commits.first.x }
    scene.branches.to_h do |branch|
      [branch.name, (branch.label.x - first_x.fetch(branch.name)).round(3)]
    end
  end

  def bottom_to_top_marker_y
    scene = scene_for(bottom_to_top_source)
    document = Nokogiri::XML(
      Sirena::Renderer::GitGraph.new.render(scene).to_xml,
    )
    document.xpath("//*[local-name()='circle']")
      .map { |circle| circle["cy"].to_f }
  end

  def generated_branch_source
    <<~MERMAID
      gitGraph:
        commit
        branch feature
        checkout feature
        commit
        checkout main
        commit
    MERMAID
  end

  def bottom_to_top_source
    <<~MERMAID
      gitGraph BT:
        commit id: "first"
        commit id: "second"
        commit id: "third"
    MERMAID
  end
end
