# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::PieSectorGeometry do
  let(:source_name) { "002_rendering_pie_spec_pie_1" }

  def measurements(svg)
    described_class.extract(svg)
  end

  def real_pair_values
    [real_reference_sector.radius, real_sirena_sector.radius,
     real_comparison.radius_error, real_comparison.sweep_error]
  end

  def real_reference_sector
    path = "spec/fixtures_mermaid/pie/#{source_name}.svg"
    @real_reference_sector ||= measurements(File.read(path)).first
  end

  def real_sirena_sector
    path = "spec/mermaid/pie/#{source_name}.mmd"
    rendered = Sirena::Engine.new.render(File.read(path))
    @real_sirena_sector ||= measurements(rendered).last
  end

  def real_comparison
    @real_comparison ||= described_class.compare(
      reference: real_reference_sector, sirena: real_sirena_sector,
    )
  end

  def real_pair_matchers
    [be_within(0.001).of(185.0), be_within(0.001).of(150.0),
     be_within(0.001).of(35.0 / 185.0), be < 0.000_01]
  end

  def transformed_svg
    <<~SVG
      <svg><g transform="translate(30 40)"><g transform="rotate(90) scale(2)">
        <path id="slice-0" d="M0 0 L10 0 A10 10 0 0 1 0 10 Z"/>
      </g></g></svg>
    SVG
  end

  def large_arc_svg
    <<~SVG
      <svg><path id="slice-0"
        d="M0 0 L10 0 A10 10 0 1 1 0 -10 Z"/></svg>
    SVG
  end

  def zero_arc_svg
    <<~SVG
      <svg><path id="slice-0"
        d="M0 0 L10 0 A0 10 0 0 1 0 10 Z"/></svg>
    SVG
  end

  def measurement_values(svg)
    sector = measurements(svg).first
    [sector.radius, sector.sweep_angle]
  end

  def transformed_matchers
    [be_within(0.000_001).of(20.0),
     be_within(0.000_001).of(Math::PI / 2)]
  end

  def zero_measurement
    described_class::Measurement.new(radius: 0.0, sweep_angle: 0.0)
  end

  def collapsed_comparison
    reference = described_class::Measurement.new(radius: 10.0,
                                                 sweep_angle: Math::PI / 2)
    described_class.compare(reference: reference, sirena: zero_measurement)
  end

  def full_error
    described_class::Comparison.new(radius_error: 1.0, sweep_error: 1.0)
  end

  it "compares the same labelled sector in a real reference and Sirena pair" do
    expect(real_pair_values).to match(real_pair_matchers)
  end

  it "composes ancestor translation, rotation, and scale" do
    expect(measurement_values(transformed_svg)).to match(transformed_matchers)
  end

  it "measures a large arc above 180 degrees" do
    expect(measurements(large_arc_svg).first.sweep_angle)
      .to be_within(0.000_001).of(3 * Math::PI / 2)
  end

  it "reports zero radius and sweep for a zero-radius arc" do
    expect(measurements(zero_arc_svg).first).to eq(zero_measurement)
  end

  it "makes a collapsed candidate a full analog error" do
    expect(collapsed_comparison).to eq(full_error)
  end
end
