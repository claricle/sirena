# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Requirement do
  subject(:diagram) { described_class.new }

  describe Sirena::Diagram::RequirementElement do
    it "appends a class name" do
      element = described_class.new

      element.add_class("external")

      expect(element.classes).to eq(["external"])
    end
  end

  describe Sirena::Diagram::RequirementRelationship do
    it "accepts a supported relationship type" do
      relationship = described_class.new(type: "contains")

      expect(relationship.valid?).to be(true)
    end

    it "rejects an unsupported relationship type" do
      relationship = described_class.new(type: "depends")

      expect(relationship.valid?).to be(false)
    end
  end

  describe Sirena::Diagram::RequirementStyle do
    it "appends a property" do
      style = described_class.new

      style.add_property("opacity:0.5")

      expect(style.properties).to eq(["opacity:0.5"])
    end
  end

  describe Sirena::Diagram::RequirementClass do
    it "appends a property" do
      requirement_class = described_class.new

      requirement_class.add_property("fill:red")

      expect(requirement_class.properties).to eq(["fill:red"])
    end
  end

  it "identifies itself as a requirement diagram" do
    expect(diagram.diagram_type).to eq(:requirement)
  end

  it "is valid without top-level content" do
    expect(diagram.valid?).to be(true)
  end
end
