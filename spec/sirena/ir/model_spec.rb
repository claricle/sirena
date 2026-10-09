# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Model do
  let(:ir_classes) do
    [
      Sirena::IR::Scalar, Sirena::IR::PropertySet, Sirena::IR::Item,
      Sirena::IR::Placement, Sirena::IR::PrepositionedItem, Sirena::IR::Edge,
      Sirena::IR::Prepositioned, Sirena::IR::Node, Sirena::IR::Graph,
      Sirena::IR::Dimension, Sirena::IR::Series, Sirena::IR::DataValue,
      Sirena::IR::Data
    ]
  end
  let(:forbidden_attributes) do
    %i[
      x y width height bounds path points routes bend_points polygon_points
      metadata layout_options mermaid plantuml arrow_type
    ]
  end

  it "loads every IR type as a strict Lutaml model" do
    expect(ir_classes).to all(be < Lutaml::Model::Serializable)
  end

  it "rejects unknown symbol and string fields" do
    attempts = [
      -> { Sirena::IR::Graph.new(id: "graph", x: 10) },
      -> { Sirena::IR::Graph.new("id" => "graph", "metadata" => {}) },
    ]

    expect { attempts.each(&:call) }.to raise_error(ArgumentError)
  end

  it "rejects unknown fields inside nested typed properties" do
    expect do
      Sirena::IR::Item.new(id: "item", properties: { arrow_type: "-->" })
    end.to raise_error(ArgumentError)
  end

  it "keeps geometry and notation spellings out of every schema" do
    exposed = ir_classes.flat_map { |model| model.attributes.keys }.uniq

    expect(exposed & forbidden_attributes).to be_empty
  end

  it "uses typed fields instead of generic hashes" do
    attribute_types = ir_classes.flat_map do |model|
      model.attributes.values.map(&:type)
    end

    expect(attribute_types).not_to include(Lutaml::Model::Type::Hash)
  end
end
