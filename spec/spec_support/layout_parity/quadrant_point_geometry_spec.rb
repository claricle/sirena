# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::QuadrantPointGeometry do
  def cohort(name)
    reference = File.read("spec/fixtures_mermaid/quadrant/#{name}.svg")
    source = File.read("spec/mermaid/quadrant/#{name}.mmd")
    [reference, Sirena.render(source)]
  end

  def comparisons(name)
    reference, sirena = cohort(name)
    described_class.compare(reference: reference, sirena: sirena)
  end

  def point_svg(label, radius)
    <<~SVG
      <svg><circle id="point-0" r="#{radius}"/><text>#{label}</text></svg>
    SVG
  end

  def styled_name
    "004_parser_should_be_able_to_parse_the_whole_chart_with_" \
      "point_styling_with_all_params_or_some_params_3"
  end

  def comparison_values(name)
    comparisons(name).map do |result|
      result.to_h.values_at(:key, :reference_radius, :sirena_radius, :error)
    end
  end

  def expected_default_values
    ("A".."F").map do |letter|
      ["Campaign #{letter}", 5.0, 6.0, be_within(0.000_001).of(0.2)]
    end
  end

  def expected_styled_values
    %w[IBM Incorta Microsoft Salesforce].map do |label|
      [label, be_within(0.000_001).of(10.0),
       be_within(0.000_001).of(10.0), be < 0.000_001]
    end
  end

  def zero_reference_errors
    [point_svg("Zero", 0), point_svg("Zero", 5)].map do |sirena|
      described_class.compare(reference: point_svg("Zero", 0), sirena: sirena)
        .first.error
    end
  end

  def two_point_svg
    extra_point = '<circle id="point-1" r="5"/><text>Two</text></svg>'
    point_svg("One", 5).sub("</svg>", extra_point)
  end

  def count_mismatch_action
    lambda do
      described_class.compare(reference: point_svg("One", 5),
                              sirena: two_point_svg)
    end
  end

  def label_mismatch_action
    lambda do
      described_class.compare(reference: point_svg("Reference", 5),
                              sirena: point_svg("Sirena", 5))
    end
  end

  def transformed_svg
    <<~SVG
      <svg><g transform="translate(30 40) scale(2)">
        <g class="data-point" transform="rotate(90) scale(3)">
          <circle r="5"/><text>Scaled point</text>
        </g>
      </g></svg>
    SVG
  end

  it "preserves the real default-radius mismatch by semantic label" do
    expect(comparison_values("001_example_quadrant-chart_0"))
      .to match(expected_default_values)
  end

  it "measures parity for the real radius-10 styled cohort" do
    expect(comparison_values(styled_name)).to match(expected_styled_values)
  end

  it "flattens nested transforms into the measured radius" do
    expect(described_class.extract(transformed_svg).first.to_h)
      .to eq(key: "Scaled point", radius: 30.0)
  end

  it "defines zero-reference analog errors" do
    expect(zero_reference_errors).to eq([0.0, Float::INFINITY])
  end

  it "refuses to drop an unmatched point" do
    expect(&count_mismatch_action)
      .to raise_error(ArgumentError, "point counts differ")
  end

  it "refuses to pair points with different labels" do
    expect(&label_mismatch_action)
      .to raise_error(ArgumentError, "point labels differ")
  end
end
