# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/end_texts"

RSpec.describe Sirena::Notation::PlantUML::EndTexts do
  def relation(**attributes)
    defaults = {
      direction: :down, left_multiplicity: "tail", left_role: "tail role",
      right_multiplicity: "head", right_role: "head role"
    }
    relation_type.new(**defaults, **attributes)
  end

  def relation_type
    @relation_type ||= Data.define(
      :direction, :left_multiplicity, :left_role,
      :right_multiplicity, :right_role
    )
  end

  def identities(entries)
    entries.map { |entry| entry.values_at(:side, :kind, :pieces) }
  end

  it "preserves dot end-text order when sort keys are equal" do
    entries = described_class.new(relation, :dot).entries

    expect(identities(entries)).to eq(
      [[:left, :multiplicity, ["tail"]],
       [:left, :role, ["tail role"]],
       [:right, :multiplicity, ["head"]],
       [:right, :role, ["head role"]]],
    )
  end

  it "moves qualifiers last without reordering ordinary smetana texts" do
    entries = described_class.new(
      relation(left_multiplicity: "[key]"), :smetana
    ).entries

    expect(identities(entries)).to eq(
      [[:right, :multiplicity, ["head"]],
       [:left, :role, ["tail role"]],
       [:right, :role, ["head role"]],
       [:left, :qualifier, ["key"]]],
    )
  end
end
