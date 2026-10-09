# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::ArchitectureRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def summaries(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent]
    end.sort_by { |item| item.map(&:to_s) }
  end

  def real_pair
    name = "002_rendering_architecture_spec_architecture_1"
    reference = reference_svg("architecture/#{name}.svg")
    sirena = Sirena.render(corpus_source("architecture/#{name}.mmd"))
    [summaries(reference), summaries(sirena)]
  end

  it "matches semantic group, service, and edge identities" do
    reference_summary, sirena_summary = real_pair

    expect(sirena_summary).to eq(reference_summary)
  end
end
