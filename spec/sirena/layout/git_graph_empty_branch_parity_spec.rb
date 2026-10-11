# frozen_string_literal: true

require "spec_helper"
require "nokogiri"

RSpec.describe Sirena::Layout::GitGraph do
  subject(:layout) { described_class.new }

  let(:branch_source) do
    <<~MERMAID
      gitGraph #{orientation}:
        commit id: "A"
        branch late order: 2
        checkout main
        branch early order: 1
        checkout main
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

  def ordered_labels
    %w[early late].map { |name| branches.fetch(name).label }
  end

  def label_baselines
    ordered_labels.map do |label|
      label.y + described_class::BRANCH_LABEL_BASELINE_OFFSET
    end
  end

  def lane_centres
    %w[early late].map do |name|
      branch = branches.fetch(name)
      creation_commit.y + (branch.lane * described_class::LANE_SPACING)
    end
  end

  def labels_precede_commits?
    ordered_labels.map(&:x).max < scene.commits.map(&:x).min
  end

  def vertical_boundary_clearance(direction)
    label_y = ordered_labels.first.y
    commit_y = scene.commits.map(&:y)
    direction == "TB" ? commit_y.min - label_y : label_y - commit_y.max
  end

  def labels_share_boundary?
    ordered_labels.map(&:y).uniq.one?
  end

  def labels_follow_lane_order?
    ordered_labels.each_cons(2).all? { |left, right| left.x < right.x }
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

  def nonempty_commits
    diagram = Sirena::Parser::GitGraph.new.parse(nonempty_source)
    layout.call(diagram).commits
  end

  def nonempty_commit_identities
    nonempty_commits.map do |commit|
      [commit.id, commit.branch, commit.lane]
    end
  end

  def nonempty_time_steps
    nonempty_commits.each_cons(2).map do |left, right|
      (right.x - left.x).round(6)
    end
  end

  def nonempty_commit_geometry
    [nonempty_commit_identities, nonempty_time_steps,
     nonempty_commits.fetch(1).y - nonempty_commits.fetch(0).y]
  end

  shared_examples "a vertical empty branch boundary" do |direction|
    let(:orientation) { direction }

    it "places #{direction} labels on one ordered boundary" do
      expect([labels_share_boundary?, vertical_boundary_clearance(direction),
              labels_follow_lane_order?]).to eq([true, 40.0, true])
    end
  end

  context "with left-to-right layout" do
    let(:orientation) { "LR" }

    it "places labels before the time axis on their assigned lanes" do
      expect([labels_precede_commits?, label_baselines == lane_centres])
        .to eq([true, true])
    end
  end

  context "with top-to-bottom layout" do
    let(:orientation) { "TB" }

    it_behaves_like "a vertical empty branch boundary", "TB"
  end

  context "with bottom-to-top layout" do
    let(:orientation) { "BT" }

    it_behaves_like "a vertical empty branch boundary", "BT"
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

  it "keeps nonempty commit geometry unchanged" do
    expect(nonempty_commit_geometry).to eq(
      [[["main-1", "main", 0], ["feature-1", "feature", 1],
        ["main-2", "main", 0]],
       [50.0, 50.0], 90.0],
    )
  end

  it "keeps lone-commit labels at Mermaid's empty-lane boundary" do
    source = <<~MERMAID
      gitGraph:
        commit
        branch test1 order: 3
        branch test2 order: 2
        branch test3 order: 1
    MERMAID
    lone_scene = layout.call(Sirena::Parser::GitGraph.new.parse(source))
    commit = lone_scene.commits.fetch(0)

    expect((lone_scene.branches.fetch(0).label.x - commit.x).round(3))
      .to eq(-86.172)
  end
end
