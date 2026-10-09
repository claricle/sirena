# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::GitGraphMarkerGeometry do
  let(:source_name) { "002_platform_showcase_base_1" }

  def reference_measurements
    path = "spec/fixtures_mermaid/gitgraph/#{source_name}.svg"
    described_class.extract(File.read(path))
  end

  def sirena_measurements
    path = "spec/mermaid/gitgraph/#{source_name}.mmd"
    described_class.extract(Sirena.render(File.read(path)))
  end

  def comparisons
    described_class.compare(reference: reference_measurements,
                            sirena: sirena_measurements)
  end

  def expected_keys
    (1..18).map { |index| "commit-#{index}" }
  end

  def real_pair_summary
    [reference_measurements.map(&:key), sirena_measurements.map(&:key),
     comparisons.map(&:key), comparisons.map(&:error)]
  end

  def expected_errors
    [0.2, 0.2, 0.2, nil, 0.2, 0.2, 0.2, 1.0 / 9, 0.2, 0.2,
     1.0 / 9, 0.2, 0.2, 1.0 / 9, 0.2, 0.2, 1.0 / 9, 1.0 / 9]
  end

  def error_matchers
    expected_errors.map do |error|
      error.nil? ? be_nil : be_within(0.000_001).of(error)
    end
  end

  def concentric_reference
    <<~SVG
      <svg>
        <circle class="commit" transform="translate(10 20)" r="9"/>
        <circle class="commit" cx="10" cy="20" r="6"/>
      </svg>
    SVG
  end

  def rectangular_reference
    <<~SVG
      <svg>
        <rect class="commit" x="0" y="0" width="20" height="20"/>
        <rect class="commit" x="4" y="4" width="12" height="12"/>
      </svg>
    SVG
  end

  def circle_svg(*radii)
    circles = radii.map { |radius| %(<circle r="#{radius}"/>) }.join
    "<svg>#{circles}</svg>"
  end

  def measurement(key, radius)
    described_class::Measurement.new(key: key, radius: radius)
  end

  def zero_reference_errors
    reference = [measurement("commit-1", 0.0)]
    [0, 5].map do |radius|
      sirena = [measurement("commit-1", radius.to_f)]
      described_class.compare(reference: reference, sirena: sirena).first.error
    end
  end

  it "compares all markers in a real reference and Sirena pair" do
    expect(real_pair_summary)
      .to match([expected_keys, expected_keys, expected_keys, error_matchers])
  end

  it "groups concentric reference circles at their transformed center" do
    expect(described_class.extract(concentric_reference))
      .to eq([measurement("commit-1", 9.0)])
  end

  it "does not assign a circular radius to a rectangular marker" do
    expect(described_class.extract(rectangular_reference))
      .to eq([measurement("commit-1", nil)])
  end

  it "defines zero-reference analog errors" do
    expect(zero_reference_errors).to eq([0.0, Float::INFINITY])
  end

  it "refuses to drop an unmatched marker" do
    reference = described_class.extract(circle_svg(5))
    sirena = described_class.extract(circle_svg(5, 5))

    expect { described_class.compare(reference: reference, sirena: sirena) }
      .to raise_error(ArgumentError, "marker counts differ")
  end

  it "refuses to pair markers with different keys" do
    reference = [measurement("commit-1", 5.0)]
    sirena = [measurement("commit-2", 5.0)]

    expect { described_class.compare(reference: reference, sirena: sirena) }
      .to raise_error(ArgumentError, "marker keys differ")
  end
end
