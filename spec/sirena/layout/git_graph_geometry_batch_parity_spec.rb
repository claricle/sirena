# frozen_string_literal: true

require "spec_helper"
require "nokogiri"

RSpec.describe Sirena::Layout::GitGraph do
  def scene_for(source)
    diagram = Sirena::Parser::GitGraph.new.parse(source)
    described_class.new.call(diagram)
  end

  it "places generated-ID branch labels at Mermaid's leading boundary" do
    scene = scene_for(<<~MERMAID)
      gitGraph:
        commit
        branch feature
        checkout feature
        commit
        checkout main
        commit
    MERMAID
    first_x = scene.commits.group_by(&:branch)
      .transform_values { |commits| commits.first.x }
    offsets = scene.branches.to_h do |branch|
      [branch.name, (branch.label.x - first_x.fetch(branch.name)).round(3)]
    end

    expect(offsets).to eq("main" => -86.172, "feature" => -151.308)
  end

  it "paints bottom-to-top markers in Mermaid's visual order" do
    scene = scene_for(<<~MERMAID)
      gitGraph BT:
        commit id: "first"
        commit id: "second"
        commit id: "third"
    MERMAID
    document = Nokogiri::XML(
      Sirena::Renderer::GitGraph.new.render(scene).to_xml,
    )
    marker_y = document.xpath("//*[local-name()='circle']")
      .map { |circle| circle["cy"].to_f }

    expect(marker_y).to eq([50.0, 100.0, 150.0])
  end
end
