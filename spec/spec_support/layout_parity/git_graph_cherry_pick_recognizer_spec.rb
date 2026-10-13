# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::GitGraphRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def commit_keys(svg)
    extract(svg, recognizer).elements.filter_map do |element|
      element.key if element.kind == :commit
    end
  end

  def keys(svg, kind)
    extract(svg, recognizer).elements.filter_map do |element|
      element.key if element.kind == kind
    end
  end

  it "recognizes a compound reference cherry-pick glyph as one commit" do
    name = "should_support_cherry_picking_commits-ecf31fda"
    source = corpus_source("gitgraph/#{name}.mmd")
    reference = reference_svg("gitgraph/#{name}.svg")

    expect([commit_keys(reference), commit_keys(Sirena.render(source))])
      .to eq([%w[commit-1 commit-2 commit-3]] * 2)
  end

  context "with known branches" do
    let(:name) { "should_generate_an_array_of_known_branches-24cef136" }
    let(:source) { corpus_source("gitgraph/#{name}.mmd") }
    let(:reference) { reference_svg("gitgraph/#{name}.svg") }
    let(:sirena) { Sirena.render(source) }

    it "keeps start-anchored branch labels out of tag identity" do
      expect([[keys(reference, :branch_label), keys(reference, :tag_label)],
              [keys(sirena, :branch_label), keys(sirena, :tag_label)]])
        .to eq([[%w[main b1 b2], []]] * 2)
    end
  end
end
