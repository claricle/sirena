# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::InfoRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent, element.label]
    end
  end

  def real_pair
    name = "001_rendering_info_spec_info_0"
    reference = reference_svg("info/#{name}.svg")
    sirena = Sirena.render(corpus_source("info/#{name}.mmd"))
    [recognized(reference), recognized(sirena)]
  end

  def expected_pair
    [[[:info_text, "info-text", nil, "v11.12.0"]],
     [[:info_text, "info-text", nil, "Info"]]]
  end

  it "uses one fixed role despite the producers' different wording" do
    expect(real_pair).to eq(expected_pair)
  end
end
