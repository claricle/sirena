# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::IR do
  include PlantUmlIrHelpers
  include PlantUmlSequenceIrHelpers

  let(:private_spelling) { /mermaid|plantuml|puml/i }

  def mermaid_vocabulary
    Sirena::Notation::Mermaid.types.flat_map do |type|
      source = File.read("spec/fixtures/contract/#{type}.mmd")
      ir_vocabulary(Sirena::Notation::Mermaid.parse(source).diagram)
    end
  end

  def plantuml_vocabulary
    graphs = [
      Sirena::Notation::PlantUML::IRAdapter.call(parse_class(feature_source)),
      Sirena::Notation::PlantUML::Sequence.parse(
        sequence_feature_source,
      ).diagram,
    ]
    graphs.flat_map { |graph| ir_vocabulary(graph) }
  end

  it "walks real Mermaid output, so the check below can fail" do
    expect(mermaid_vocabulary.length).to be > 100
  end

  it "walks real PlantUML output, so the check below can fail" do
    expect(plantuml_vocabulary).to include("abstract_class")
  end

  it "names no notation in any Mermaid role, marker or dimension" do
    expect(mermaid_vocabulary.grep(private_spelling)).to be_empty
  end

  it "names no notation in any PlantUML role, marker or dimension" do
    expect(plantuml_vocabulary.grep(private_spelling)).to be_empty
  end
end
