# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::MindmapRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def keys(svg)
    extract(svg, recognizer).elements.map(&:key)
  end

  def real_pair
    name = "009_rendering_mindmap_spec_mindmap_8"
    reference = reference_svg("mindmap/#{name}.svg")
    sirena = Sirena.render(corpus_source("mindmap/#{name}.mmd"))
    [keys(reference), keys(sirena)]
  end

  it "uses the same semantic labels for a real multi-level pair" do
    reference_keys, sirena_keys = real_pair

    expect(sirena_keys).to eq(reference_keys)
  end
end
