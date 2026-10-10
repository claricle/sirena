# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::GitGraphRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
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
    source = "gitGraph #{orientation}:\n commit\n branch x\n " \
             "checkout x\n commit\n"
    keys_of(recognized(Sirena.render(source)), :lane)
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

  it "recognizes vertical candidate lanes from collinear markers" do
    lanes = %w[TB BT].map { |orientation| vertical_lane_keys(orientation) }

    expect(lanes).to eq([%w[main x], %w[main x]])
  end
end
