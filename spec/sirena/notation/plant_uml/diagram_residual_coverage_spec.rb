# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/diagram"

RSpec.describe Sirena::Notation::PlantUML::Diagram do
  it "identifies a completed class diagram as valid" do
    diagram = described_class.new(classes: [:account], relations: [])

    expect([diagram.valid?, diagram.diagram_type])
      .to eq([true, :class_diagram])
  end
end
