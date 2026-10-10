# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::IR::Item do
  it "defines the shared notation-neutral vocabulary" do
    expect(described_class.attributes.keys)
      .to eq(%i[
               id label role parent_id accessibility_title
               accessibility_description properties
             ])
  end

  it "does not share default property sets between items" do
    first = described_class.new(id: "first")
    second = described_class.new(id: "second")
    distinct_properties = !first.properties.equal?(second.properties)

    expect([first.valid?, second.valid?, distinct_properties])
      .to eq([true, true, true])
  end

  it "requires identity and a normalized notation-neutral role" do
    roles = [nil, "graph_node", "Graph Node", "mermaid", "plantuml_class"]
    results = roles.map do |role|
      described_class.new(id: "item", role: role).valid?
    end

    expect(results).to eq([true, true, false, false, false])
  end

  it "rejects a missing identity" do
    expect(ir_messages(described_class, id: ""))
      .to include("id must be a nonempty String")
  end

  it "rejects an invalid property set" do
    bad = Sirena::IR::PropertySet.new(weight: -1)
    expect(ir_messages(described_class, id: "i", properties: bad))
      .to include("properties must be a valid PropertySet")
  end

  it "rejects a missing property set" do
    expect(ir_messages(described_class, id: "i", properties: nil))
      .to include("properties must be a valid PropertySet")
  end

  it "uses an exact closed property vocabulary" do
    expect(Sirena::IR::PropertySet.attributes.keys)
      .to eq(%i[source_marker target_marker weight])
  end

  context "with valid and invalid property values" do
    subject(:validity) { properties.map(&:valid?) }

    let(:properties) do
      [
        Sirena::IR::PropertySet.new(source_marker: "open_circle", weight: 0),
        Sirena::IR::PropertySet.new(target_marker: "Open circle"),
        Sirena::IR::PropertySet.new(weight: -1),
        Sirena::IR::PropertySet.new(weight: Float::INFINITY),
      ]
    end

    it "validates normalized markers and finite nonnegative weights" do
      expect(validity).to eq([true, false, false, false])
    end
  end
end
