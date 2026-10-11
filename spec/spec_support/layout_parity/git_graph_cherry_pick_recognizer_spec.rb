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

  it "recognizes a compound reference cherry-pick glyph as one commit" do
    name = "should_support_cherry_picking_commits-ecf31fda"
    source = corpus_source("gitgraph/#{name}.mmd")
    reference = reference_svg("gitgraph/#{name}.svg")

    expect([commit_keys(reference), commit_keys(Sirena.render(source))])
      .to eq([%w[commit-1 commit-2 commit-3]] * 2)
  end
end
