# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"
Sirena::Notation.send(:entries).delete(:plantuml)

# Geometry below is measured from PlantUML 1.2026.6 (the pinned reference).
RSpec.describe Sirena::Notation::PlantUML::MemberPitch do
  def offsets(kinds, titles = Array.new(kinds.size, "x"), **options)
    described_class.layout(kinds, titles, **options)
  end

  it "steps a row at a time" do
    expect(offsets(%i[field field]).first).to eq([(8.0 * 0) + 0.0, 16.48828125])
  end

  it "adds the gap between a field group and a method group" do
    expect(offsets(%i[field method]).first).to eq([0.0, 24.48828125])
  end

  it "adds the extent of both compartments to a box" do
    expect(offsets(%i[field method]).last).to eq(40.97656250)
  end

  it "keeps the empty method compartment below fields only" do
    expect(offsets(%i[field field]).last).to eq(40.9765625)
  end

  it "keeps the empty field compartment above methods only" do
    expect(offsets(%i[method])).to eq([[8.0], 24.48828125])
  end

  it "drops those gaps when members are hidden" do
    expect(offsets(%i[method], gaps: false)).to eq([[0.0], 16.48828125])
  end

  it "sets a titled separator as a row 3.5 low that pushes the rest 4" do
    kinds = %i[method separator method]

    expect(offsets(kinds, ["a", "t", "b"]).first)
      .to eq([0.0, 16.48828125 + 3.5, (2 * 16.48828125) + 4.0])
  end

  it "sets a bare separator as 8 of gap, its rule 6.95 under the row before" do
    kinds = %i[field separator field]

    expect(offsets(kinds, ["a", "", "b"]).first)
      .to eq([0.0, 10.95, 16.48828125 + 8.0])
  end

  it "drops the empty method compartment of fields split by a separator" do
    extent = offsets(%i[field separator field], ["a", "", "b"]).last

    expect(extent).to eq((2 * 16.48828125) + 8.0)
  end

  it "drops the empty field compartment of methods split by a separator" do
    expect(offsets(%i[method separator method]).first.first).to eq(0.0)
  end
end
