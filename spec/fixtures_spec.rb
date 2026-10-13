# frozen_string_literal: true

require "spec_helper"

module ReferenceFixtureSpecHelpers
  def length_band_message(actual_svg, expected_svg, diagram_type, baseline)
    ratio = length_ratio(actual_svg, expected_svg).round(4)
    "ratio #{ratio} is outside 2x of the #{diagram_type} baseline #{baseline}"
  end
end

RSpec.describe "Reference SVG Fixtures" do
  include ReferenceFixtureSpecHelpers
  include FixtureLengthBand

  let(:engine) { Sirena::Engine.new }

  shared_examples(
    "validates against reference fixture",
  ) do |diagram_type, baseline_ratio|
    let(:input_path) do
      SpecSupport::RepositoryPaths.path("spec/fixtures/#{diagram_type}/input.mmd")
    end
    let(:expected_path) do
      SpecSupport::RepositoryPaths.path("spec/fixtures/#{diagram_type}/expected.svg")
    end
    let(:actual_svg) { engine.render(File.read(input_path)) }
    let(:expected_svg) { File.read(expected_path) }

    before { actual_svg }

    it "generates SVG text" do
      expect(actual_svg).to be_a(String)
    end

    it "generates nonempty output" do
      expect(actual_svg).not_to be_empty
    end

    it "includes an opening SVG tag" do
      expect(actual_svg).to include("<svg")
    end

    it "includes a closing SVG tag" do
      expect(actual_svg).to include("</svg>")
    end

    it "includes the expected root structure" do
      expect(actual_svg).to match(/<svg[^>]*>/)
    end

    it "closes the expected root structure" do
      expect(actual_svg).to include("</svg>")
    end

    it "includes graphical elements" do
      expect(actual_svg).to match(/<g[^>]*>|<rect[^>]*>|<path[^>]*>/)
    end

    it "starts the actual output with SVG" do
      expect(actual_svg).to start_with("<svg")
    end

    it "starts the reference output with SVG" do
      expect(expected_svg).to start_with("<svg")
    end

    # A per-type band rejects collapse relative to the measured baseline.
    it "produces output comparable to reference" do
      message = length_band_message(actual_svg, expected_svg,
                                    diagram_type, baseline_ratio)
      expect(within_length_band?(actual_svg, expected_svg, baseline_ratio))
        .to be(true), message
    end

    it "fails the length band when the output is 50x smaller" do
      collapsed = actual_svg[0, actual_svg.length / 50]

      expect(within_length_band?(collapsed, expected_svg,
                                 baseline_ratio)).to be(false)
    end

    it "fails the length band when the output is 3x larger" do
      expect(within_length_band?(actual_svg * 3, expected_svg,
                                 baseline_ratio)).to be(false)
    end
  end

  describe "Flowchart diagrams" do
    it_behaves_like "validates against reference fixture", "flowchart", 0.28
  end

  describe "Sequence diagrams" do
    it_behaves_like "validates against reference fixture", "sequence", 0.25
  end

  describe "Class diagrams" do
    it_behaves_like "validates against reference fixture", "class_diagram", 0.26
  end

  describe "State diagrams" do
    it_behaves_like "validates against reference fixture", "state_diagram",
                    0.024
  end

  describe "ER diagrams" do
    it_behaves_like "validates against reference fixture", "er_diagram", 0.11
  end

  describe "User journey diagrams" do
    it_behaves_like "validates against reference fixture", "user_journey", 0.47
  end

  describe "XY Chart diagrams" do
    it_behaves_like "validates against reference fixture", "xy_chart", 1.48
  end

  describe "Sankey diagrams" do
    it_behaves_like "validates against reference fixture", "sankey", 1.0
  end

  describe "Length band" do
    it "rejects output 50x smaller than the reference" do
      expect(FixtureLengthBand.cover?(1.0 / 50)).to be(false)
    end

    it "rejects output more than twice the reference" do
      expect(FixtureLengthBand.cover?(2.01)).to be(false)
    end

    it "accepts output the size of the reference" do
      expect(FixtureLengthBand.cover?(1.0)).to be(true)
    end
  end

  describe "Fixture completeness" do
    %w[
      flowchart sequence class_diagram state_diagram er_diagram
      user_journey xy_chart sankey
    ].each do |type|
      it "has the input fixture for #{type}" do
        input = SpecSupport::RepositoryPaths.path("spec/fixtures/#{type}/input.mmd")
        expect(File).to exist(input), "Missing input fixture for #{type}"
      end

      it "has the expected SVG fixture for #{type}" do
        expected = SpecSupport::RepositoryPaths.path("spec/fixtures/#{type}/expected.svg")
        expect(File).to exist(expected), "Missing expected SVG for #{type}"
      end
    end
  end
end
