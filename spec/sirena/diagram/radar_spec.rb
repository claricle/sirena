# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/radar"

RSpec.describe Sirena::Diagram::Radar do
  subject(:diagram) { described_class.new }

  let(:axis) { Sirena::Diagram::RadarAxis.new("speed", "Speed") }
  let(:curve) { Sirena::Diagram::RadarCurve.new("baseline", "Baseline") }

  it "starts empty and reports its model contract" do
    expect(
      [diagram.axes, diagram.curves, diagram.options,
       diagram.diagram_type, diagram.valid?],
    ).to eq([[], [], {}, :radar, true])
  end

  it "stores numeric curve values by axis" do
    curve.add_value(axis.id, "7.5")
    values = [axis.label, curve.label, curve.value_for(axis.id),
              curve.value_for("missing")]
    expect(values).to eq(["Speed", "Baseline", 7.5, 0.0])
  end
end
