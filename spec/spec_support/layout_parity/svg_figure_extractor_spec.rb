# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::SvgFigureExtractor do
  include SpecSupport::LayoutParity::FigureHelpers

  let(:flowchart) { SpecSupport::LayoutParity::FlowchartRecognizer.new }
  let(:sequence) { SpecSupport::LayoutParity::SequenceRecognizer.new }

  describe "nested transforms (contract section 2)" do
    {
      "translate then scale" => ["a", [20.0, 30.0, 40.0, 40.0]],
      "rotate(90) under a translate" => ["b", [6.0, 20.0, 10.0, 30.0]],
      "matrix on a circle" => ["c", [20.0, 30.0, 30.0, 50.0]],
    }.each do |name, (key, expected)|
      it "composes #{name}" do
        figure = figure_of("nested_transforms.svg", flowchart)

        expect(box_of(figure, key)).to eq(expected)
      end
    end

    it "composes a nested svg viewBox with meet" do
      figure = figure_of("nested_svg_viewport.svg", flowchart)

      expect(box_of(figure, "icon")).to eq([10.0, 10.0, 30.0, 20.0])
    end

    it "composes a nested svg viewBox with xMinYMin slice" do
      figure = figure_of("nested_svg_viewport.svg", flowchart)

      expect(box_of(figure, "slice")).to eq([0.0, 0.0, 40.0, 20.0])
    end

    it "rejects a transform function outside the contract" do
      expect { extract(skewed_svg, flowchart) }
        .to raise_error(ArgumentError, /skewX/)
    end
  end

  describe "scale and translation (contract section 2)" do
    it "reports numbers in viewBox units, ignoring width and height" do
      figure = figure_of("root_viewbox_offset.svg", flowchart)

      expect([box_of(figure, "a"), figure.root_box.to_a])
        .to eq([[110.0, 60.0, 130.0, 70.0], [100.0, 50.0, 300.0, 150.0]])
    end

    {
      "no viewBox falls back to width and height" =>
        ['width="30" height="20"', [0.0, 0.0, 30.0, 20.0]],
      "percentage sizes leave the root user space unmapped" =>
        ['width="100%" height="100%"', nil],
    }.each do |name, (attrs, expected)|
      it name do
        svg = %(<svg xmlns="http://www.w3.org/2000/svg" #{attrs}></svg>)

        expect(extract(svg, flowchart).root_box&.to_a).to eq(expected)
      end
    end

    it "keeps the max-width style as the fallback extent" do
      svg = '<svg width="100%" style="max-width: 400px;"></svg>'

      expect(extract(svg, flowchart).max_width).to eq(400.0)
    end
  end

  describe "text anchors (contract section 2)" do
    it "uses text x/y plus text and first tspan dx/dy, through transforms" do
      figure = figure_of("text_anchor.svg", flowchart)

      expect(box_of(figure, "t")).to eq([16.0, 21.0, 16.0, 21.0])
    end

    it "takes the position from the first positioned tspan" do
      figure = figure_of("text_anchor.svg", flowchart)

      expect(box_of(figure, "u")).to eq([17.0, 18.0, 17.0, 18.0])
    end
  end

  describe "parents (contract section 1)" do
    it "records the smallest enclosing cluster, nothing at the root" do
      parents = parents_of(figure_of("ancestry.svg", flowchart))

      expect(parents).to eq("outer" => nil, "inner" => "outer",
                            "deep" => "inner", "mid" => "outer", "free" => nil)
    end

    it "reads the nested subgraphs of a real mmdc reference" do
      name = "079_parser_should_handle_nested_subgraphs_3_74"
      figure = extract(reference_svg("flowchart/#{name}.svg"), flowchart)

      expect(parents_of(figure)).to eq(nested_subgraph_parents)
    end

    it "gives a Sirena render the same parents" do
      svg = Sirena.render(nested_subgraphs_source)

      expect(parents_of(extract(svg, flowchart)))
        .to eq(nested_subgraph_parents)
    end
  end

  describe "one code path for reference and Sirena" do
    it "gives a flowchart the same (kind, parent, key) set on both sides" do
      keys = flowchart_sides("001_config_0").map do |svg|
        extract(svg, flowchart).keys.sort_by(&:last)
      end

      expected = %w[A B C D E F].map { |id| [:node, nil, id] }
      expect(keys).to eq([expected, expected])
    end

    it "gives sequence participants the same keys on both sides" do
      reference, sirena = sequence_sides
      sirena_keys = extract(sirena, sequence).keys.sort_by(&:last)

      expect([participant_tops(reference, sequence), sirena_keys])
        .to eq([expected_tops, expected_tops])
    end

    it "separates a reference participant's top and bottom boxes" do
      reference, = sequence_sides
      kinds = extract(reference, sequence).keys.map(&:first)

      expect(kinds.uniq.sort).to eq(%i[participant-bottom participant-top])
    end
  end
end
