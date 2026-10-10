# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::IRReader do
  include PlantUmlIrHelpers

  def round_trip(diagram)
    described_class.call(Sirena::Notation::PlantUML::IRAdapter.call(diagram))
  end

  it "rebuilds a diagram using every construct" do
    diagram = parse_class(feature_source)

    expect(summary(round_trip(diagram))).to eq(summary(diagram))
  end

  it "rebuilds every corpus diagram the parser accepts" do
    diagrams = corpus_diagrams

    expect(diagrams.map { |d| summary(round_trip(d)) })
      .to eq(diagrams.map { |d| summary(d) })
  end

  it "has corpus diagrams to rebuild" do
    expect(corpus_diagrams.size).to be > 30
  end
end
