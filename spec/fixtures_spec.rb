# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reference SVG Fixtures' do
  include FixtureLengthBand

  let(:engine) { Sirena::Engine.new }

  shared_examples 'validates against reference fixture' do |diagram_type, baseline_ratio|
    let(:input_path) { File.expand_path("fixtures/#{diagram_type}/input.mmd", __dir__) }
    let(:expected_path) { File.expand_path("fixtures/#{diagram_type}/expected.svg", __dir__) }
    let(:input_mmd) { File.read(input_path) }
    let(:expected_svg) { File.read(expected_path) }

    it 'generates valid SVG output' do
      actual_svg = engine.render(input_mmd)

      expect(actual_svg).to be_a(String)
      expect(actual_svg).not_to be_empty
      expect(actual_svg).to include('<svg')
      expect(actual_svg).to include('</svg>')
    end

    it 'includes expected SVG structure elements' do
      actual_svg = engine.render(input_mmd)

      # Verify basic SVG structure
      expect(actual_svg).to match(/<svg[^>]*>/)
      expect(actual_svg).to include('</svg>')

      # Verify presence of graphical elements
      expect(actual_svg).to match(/<g[^>]*>|<rect[^>]*>|<path[^>]*>/)
    end

    it 'produces output comparable to reference' do
      actual_svg = engine.render(input_mmd)

      # Note: We don't require exact match due to implementation differences
      # Instead, verify structural similarity

      # Both should be valid SVG
      expect(actual_svg).to start_with('<svg')
      expect(expected_svg).to start_with('<svg')

      # Sirena's output is a per-type fraction of Mermaid's size. The band is
      # centred on that type's measured ratio (see FixtureLengthBand), so a
      # collapse to a fraction of today's output fails, not just a collapse
      # to 2% of the reference.
      ratio = length_ratio(actual_svg, expected_svg).round(4)
      expect(within_length_band?(actual_svg, expected_svg, baseline_ratio))
        .to be(true), "ratio #{ratio} is outside 2x of the #{diagram_type} baseline #{baseline_ratio}"
    end

    it 'fails the length band when the output is 50x smaller' do
      actual_svg = engine.render(input_mmd)
      collapsed = actual_svg[0, actual_svg.length / 50]

      expect(within_length_band?(collapsed, expected_svg, baseline_ratio)).to be(false)
    end

    it 'fails the length band when the output is 3x larger' do
      actual_svg = engine.render(input_mmd)

      expect(within_length_band?(actual_svg * 3, expected_svg, baseline_ratio)).to be(false)
    end
  end

  describe 'Flowchart diagrams' do
    include_examples 'validates against reference fixture', 'flowchart', 0.28
  end

  describe 'Sequence diagrams' do
    include_examples 'validates against reference fixture', 'sequence', 0.25
  end

  describe 'Class diagrams' do
    include_examples 'validates against reference fixture', 'class_diagram', 0.26
  end

  describe 'State diagrams' do
    include_examples 'validates against reference fixture', 'state_diagram', 0.024
  end

  describe 'ER diagrams' do
    include_examples 'validates against reference fixture', 'er_diagram', 0.11
  end

  describe 'User journey diagrams' do
    include_examples 'validates against reference fixture', 'user_journey', 0.47
  end

  describe 'XY Chart diagrams' do
    include_examples 'validates against reference fixture', 'xy_chart', 1.48
  end

  describe 'Sankey diagrams' do
    include_examples 'validates against reference fixture', 'sankey', 1.0
  end

  describe 'Length band' do
    it 'rejects output 50x smaller than the reference' do
      expect(FixtureLengthBand.cover?(1.0 / 50)).to be(false)
    end

    it 'rejects output more than twice the reference' do
      expect(FixtureLengthBand.cover?(2.01)).to be(false)
    end

    it 'accepts output the size of the reference' do
      expect(FixtureLengthBand.cover?(1.0)).to be(true)
    end
  end

  describe 'Fixture completeness' do
    it 'has fixtures for all supported diagram types' do
      expected_types = %w[
        flowchart
        sequence
        class_diagram
        state_diagram
        er_diagram
        user_journey
        xy_chart
        sankey
      ]

      expected_types.each do |type|
        input = File.expand_path("fixtures/#{type}/input.mmd", __dir__)
        expected = File.expand_path("fixtures/#{type}/expected.svg", __dir__)

        expect(File).to exist(input),
                        "Missing input fixture for #{type}"
        expect(File).to exist(expected),
                        "Missing expected SVG for #{type}"
      end
    end
  end
end