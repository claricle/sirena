# frozen_string_literal: true

require "spec_helper"
require "digest"
require "nokogiri"

RSpec.describe Sirena::Layout::GitGraph do
  subject(:layout) { described_class.new }

  let(:branch_source) do
    <<~MERMAID
      gitGraph #{orientation}:
        commit id: "A"
        branch late order: 2
        branch early order: 1
        commit id: "B"
    MERMAID
  end
  let(:orientation) { "LR" }
  let(:scene) { layout.call(Sirena::Parser::GitGraph.new.parse(branch_source)) }
  let(:branches) { scene.branches.to_h { |branch| [branch.name, branch] } }

  def creation_commit
    scene.commits.find { |commit| commit.id == "A" }
  end

  def nonempty_source
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

  def anchor_for(branch, direction)
    label = branch.label
    case direction
    when "TB" then [label.x, label.y - 24]
    when "BT" then [label.x, label.y + 16]
    else [label.x - 15, label.y - 4]
    end
  end

  def expected_anchor(branch, direction)
    lane_offset = branch.lane * described_class::LANE_SPACING
    if %w[TB BT].include?(direction)
      [creation_commit.x + lane_offset, creation_commit.y]
    else
      [creation_commit.x, creation_commit.y + lane_offset]
    end
  end

  def actual_anchors(direction)
    %w[early late].to_h do |name|
      [name, anchor_for(branches.fetch(name), direction)]
    end
  end

  def expected_anchors(direction)
    %w[early late].to_h do |name|
      [name, expected_anchor(branches.fetch(name), direction)]
    end
  end

  def rendered_branch_evidence
    document = rendered_document
    [label_count(document, "early"), label_count(document, "late"),
     marker_count(document), *graph_marker_evidence]
  end

  def rendered_document
    Nokogiri::XML(
      Sirena::Renderer::GitGraph.new.render(scene).to_xml,
    )
  end

  def label_count(document, label)
    document.xpath("//*[local-name()='text']").count do |node|
      node.text == label
    end
  end

  def marker_count(document)
    document.xpath("//*[local-name()='circle']").size
  end

  def graph_marker_evidence
    [scene.commits.map(&:id), scene.connections.size]
  end

  def rendering_digest(source)
    diagram = Sirena::Parser::GitGraph.new.parse(source)
    svg = Sirena::Renderer::GitGraph.new.render(layout.call(diagram)).to_xml
    Digest::SHA256.hexdigest(svg)
  end

  shared_examples "an empty branch anchor" do |direction|
    let(:orientation) { direction }

    it "uses the creation time and assigned lane for #{direction}" do
      expect(actual_anchors(direction)).to eq(expected_anchors(direction))
    end
  end

  context "with left-to-right layout" do
    let(:orientation) { "LR" }

    it_behaves_like "an empty branch anchor", "LR"
  end

  context "with top-to-bottom layout" do
    let(:orientation) { "TB" }

    it_behaves_like "an empty branch anchor", "TB"
  end

  context "with bottom-to-top layout" do
    let(:orientation) { "BT" }

    it_behaves_like "an empty branch anchor", "BT"
  end

  it "honours explicit branch order when assigning empty lanes" do
    evidence = %w[early late].to_h do |name|
      branch = branches.fetch(name)
      [name, branch.lane]
    end

    expect(evidence).to eq("early" => 1, "late" => 2)
  end

  it "renders each empty branch label once without synthetic graph markers" do
    expect(rendered_branch_evidence).to eq([1, 1, 2, %w[A B], 1])
  end

  it "keeps nonempty branch rendering byte-identical" do
    expect(rendering_digest(nonempty_source))
      .to eq("5d1a663c90fd10f89173bfeec793563a14c7608fde34ab8e4c9e1ce8234e31ae")
  end
end
