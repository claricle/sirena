# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Sequence::IRReader do
  include PlantUmlSequenceIrHelpers

  def round_trip(diagram)
    adapter = Sirena::Notation::PlantUML::Sequence::IRAdapter
    described_class.call(adapter.call(diagram))
  end

  it "rebuilds a diagram using every construct" do
    diagram = parse_sequence(sequence_feature_source)

    expect(sequence_shape(round_trip(diagram))).to eq(sequence_shape(diagram))
  end

  it "rebuilds every corpus diagram the parser accepts" do
    diagrams = sequence_corpus_diagrams

    expect(diagrams.map { |d| sequence_shape(round_trip(d)) })
      .to eq(diagrams.map { |d| sequence_shape(d) })
  end

  it "has corpus diagrams to rebuild" do
    expect(sequence_corpus_diagrams.size).to be > 60
  end
end
