# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/state/cluster_padding"

# Measured with the PlantUML 1.2026.6 JAR: a composite with no transition at
# its border keeps 13 below its children and 24 at their right; one with a
# transition from a state inside to one outside keeps 16; and one that also
# has a transition ending at itself keeps 24.
RSpec.describe Sirena::Notation::PlantUML::State::ClusterPadding do
  let(:parent) do
    { "in" => "box", "deep" => "inner", "inner" => "box", "box" => nil,
      "out" => nil }
  end

  def padding(*pairs)
    edges = pairs.map { |from, to| { sources: [from], targets: [to] } }
    described_class.new(edges, parent).room("box")
  end

  it "keeps a composite with no transition at its border bare" do
    expect(padding(%w[in deep])).to have_attributes(left: 24, right: 24,
                                                    bottom: 13, title: 20)
  end

  it "keeps a composite that only a transition ends at bare" do
    expect(padding(%w[out box], %w[box out])).to have_attributes(bottom: 13)
  end

  it "keeps a composite and its own child, joined, bare" do
    expect(padding(%w[box in])).to have_attributes(bottom: 13)
  end

  it "gives a state inside that leaves for one outside 16 on every side" do
    expect(padding(%w[in out])).to have_attributes(left: 16, right: 16,
                                                   bottom: 16, title: 15.5)
  end

  it "counts a state nested deeper as inside" do
    expect(padding(%w[out deep])).to have_attributes(bottom: 16)
  end

  it "gives a composite with both kinds of transition 24 on every side" do
    expect(padding(%w[in out], %w[out box]))
      .to have_attributes(left: 24, right: 24, bottom: 24, title: 15.5)
  end
end
