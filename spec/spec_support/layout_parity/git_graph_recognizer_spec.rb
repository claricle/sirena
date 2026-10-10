# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::GitGraphRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized_elements(svg)
    extract(svg, recognizer).elements
  end

  def recognized(svg)
    recognized_elements(svg).map do |element|
      [element.kind, element.key, element.identity]
    end
  end

  def real_pair
    name = "002_platform_showcase_base_1"
    reference = reference_svg("gitgraph/#{name}.svg")
    sirena = Sirena.render(corpus_source("gitgraph/#{name}.mmd"))
    [recognized(reference), recognized(sirena)]
  end

  def keys_of(elements, kind)
    elements.select { |item| item.first == kind }.map { |item| item[1] }
  end

  def real_summary
    real_pair.map do |elements|
      [keys_of(elements, :commit), keys_of(elements, :branch_label),
       keys_of(elements, :lane)]
    end
  end

  def expected_commits
    (1..18).map { |index| "commit-#{index}" }
  end

  def expected_branches
    %w[main hotfix develop featureB featureA release]
  end

  def vertical_lane_keys(orientation)
    source = <<~MERMAID
      gitGraph #{orientation}:
       commit
       branch x
       checkout x
       commit
    MERMAID
    keys_of(recognized(Sirena.render(source)), :lane)
  end

  def lane_dimensions(svg)
    recognized_elements(svg).filter_map do |element|
      next unless element.kind == :lane

      [element.bbox.width, element.bbox.height]
    end
  end

  def real_svgs
    name = "002_platform_showcase_base_1"
    [reference_svg("gitgraph/#{name}.svg"),
     Sirena.render(corpus_source("gitgraph/#{name}.mmd"))]
  end

  it "uses marker ordinals and semantic branch labels on a real pair" do
    expected = [expected_commits, expected_branches]

    expect(real_summary.map { |side| side.first(2) })
      .to eq([expected, expected])
  end

  it "recognizes semantic lanes from both rendered representations" do
    reference, sirena = real_summary.map(&:last)

    expect([reference, sirena]).to eq([expected_branches, expected_branches])
  end

  it "uses zero-area anchors for semantic lanes" do
    dimensions = real_svgs.flat_map { |svg| lane_dimensions(svg) }

    expect(dimensions).to all(eq([0.0, 0.0]))
  end

  it "recognizes vertical candidate lanes from marker-associated labels" do
    lanes = %w[TB BT].map { |orientation| vertical_lane_keys(orientation) }

    expect(lanes).to eq([%w[main x], %w[main x]])
  end
end
