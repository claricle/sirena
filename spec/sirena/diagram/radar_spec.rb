# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/radar"

RSpec.describe Sirena::Diagram::Radar do
  subject(:diagram) { described_class.new }

  it "starts empty and reports its model contract" do
    expect(
      [diagram.axes, diagram.curves, diagram.options,
       diagram.diagram_type, diagram.valid?],
    ).to eq([[], [], {}, :radar, true])
  end

  it "stores numeric curve values by axis" do
    axis = Sirena::Diagram::RadarAxis.new("speed", "Speed")
    curve = Sirena::Diagram::RadarCurve.new("baseline", "Baseline")
    curve.add_value(axis.id, "7.5")

    expect(
      [axis.label, curve.label,
       curve.value_for(axis.id), curve.value_for("missing")],
    ).to eq(["Speed", "Baseline", 7.5, 0.0])
  end
end
