# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Words that exist only because one notation spells a construct its own way,
# or that name a source language (TODO.foundation/18, "What notation-neutral
# means here"). Matched against a name with its underscores removed.
#
# Deliberately absent: words both notations share (participant) and generic
# UML terms (stereotype). The sequence adapters of Mermaid and PlantUML both
# emit a "participant" role; that is shared vocabulary, not a leak.
module IrNotationVocabulary
  WORDS = %w[
    mermaid plantuml puml startuml enduml
    classdef linkstyle subgraph skinparam
  ].freeze

  def self.leaks(name)
    squeezed = name.to_s.downcase.delete("_")
    WORDS.select { |word| squeezed.include?(word) }
  end
end

# Everything the IR exposes by name, read from the classes, and every
# role/marker value an adapter put into an IR tree.
module IrNeutralityProbe
  def ir_classes
    Sirena::IR.constants.map { |name| Sirena::IR.const_get(name) }
      .select { |const| const.is_a?(Class) && const <= Sirena::IR::Model }
  end

  def declared_names(klass)
    readers = klass.public_instance_methods(false).map(&:to_s)
      .reject { |name| name.start_with?("__") || name.end_with?("=") }
    klass.attributes.keys.map(&:to_s) | readers
  end

  def vocabulary_leaks(klass)
    declared_names(klass)
      .to_h { |name| [name, IrNotationVocabulary.leaks(name)] }
      .reject { |_, words| words.empty? }
  end

  def walk(model, &block)
    yield model
    model.class.attributes.each_key do |name|
      Array(model.public_send(name)).each do |child|
        walk(child, &block) if child.is_a?(Sirena::IR::Model)
      end
    end
  end

  def value_leaks(root)
    vocabulary_values(root)
      .flat_map { |value| IrNotationVocabulary.leaks(value) }.uniq
  end

  def vocabulary_values(root)
    seen = []
    walk(root) do |model|
      %i[role source_marker target_marker].each do |name|
        seen << model.public_send(name) if model.respond_to?(name)
      end
    end
    seen.compact
  end

  def mermaid_trees
    Sirena::Notation::Mermaid.types.to_h do |type|
      source = File.read("spec/fixtures/contract/#{type}.mmd")
      [type, Sirena::Notation::Mermaid.parse(source).diagram]
    end
  end

  def plantuml_trees
    {
      class: Sirena::Notation::PlantUML::IRAdapter
        .call(parse_class(feature_source)),
      sequence: Sirena::Notation::PlantUML::Sequence::IRAdapter
        .call(parse_sequence(sequence_feature_source)),
    }
  end
end

RSpec.describe Sirena::IR do
  include PlantUmlIrHelpers
  include PlantUmlSequenceIrHelpers
  include IrNeutralityProbe

  let(:trees) do
    mermaid_trees.merge(
      plantuml_trees.transform_keys { |key| :"plantuml_#{key}" },
    )
  end

  it "covers every IR class, so a new one cannot escape the check" do
    expect(ir_classes.map { |klass| klass.name.split("::").last }).to include(
      "Item", "Node", "Edge", "Graph", "Data", "DataValue", "Dimension",
      "Series", "Placement", "Prepositioned", "PrepositionedItem",
      "PropertySet", "Scalar"
    )
  end

  it "names no notation-only construct in any IR field or reader" do
    leaks = ir_classes.to_h { |klass| [klass.name, vocabulary_leaks(klass)] }
      .reject { |_, found| found.empty? }

    expect(leaks).to eq({})
  end

  it "flags a notation-named field, so the check above can fail" do
    probe = Class.new(Sirena::IR::Node) { attribute :class_def_style, :string }

    expect(vocabulary_leaks(probe)).to eq("class_def_style" => ["classdef"])
  end

  it "reads adapter output from every Mermaid type and both PlantUML slices" do
    expect(trees.keys).to include(*Sirena::Notation::Mermaid.types,
                                  :plantuml_class, :plantuml_sequence)
  end

  it "puts no notation-only word in any role or marker an adapter emits" do
    leaks = trees.transform_values { |root| value_leaks(root) }
    leaks = leaks.reject { |_, found| found.empty? }

    expect(leaks).to eq({})
  end

  it "actually inspects roles in the adapter output" do
    counts = trees.transform_values { |root| vocabulary_values(root).size }

    expect(counts.values.sum).to be > 100
  end
end
