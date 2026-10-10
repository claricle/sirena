# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Requirement do
  subject(:diagram) { described_class.new }

  describe Sirena::Diagram::RequirementNode do
    it "adds a class name" do
      node = described_class.new
      node.add_class("critical")
      expect(node.classes).to eq(["critical"])
    end
  end

  describe Sirena::Diagram::RequirementStyle do
    it "adds a target" do
      style = described_class.new
      style.add_target("R1")
      expect(style.target_ids).to eq(["R1"])
    end
  end

  describe Sirena::Diagram::RequirementClassAssignment do
    it "adds targets and class names" do
      assignment = described_class.new
      assignment.add_target("R1")
      assignment.add_class("critical")
      expect([assignment.target_ids, assignment.class_names])
        .to eq([["R1"], ["critical"]])
    end
  end

  {
    requirement: [Sirena::Diagram::RequirementNode, :requirements],
    element: [Sirena::Diagram::RequirementElement, :elements],
    relationship: [Sirena::Diagram::RequirementRelationship, :relationships],
    style: [Sirena::Diagram::RequirementStyle, :styles],
    class: [Sirena::Diagram::RequirementClass, :classes],
    class_assignment: [
      Sirena::Diagram::RequirementClassAssignment,
      :class_assignments,
    ],
  }.each do |kind, (model, collection)|
    it "appends #{kind} values" do
      item = model.new
      diagram.public_send("add_#{kind}", item)
      expect(diagram.public_send(collection)).to eq([item])
    end
  end
end
