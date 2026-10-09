# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::SvgFigureExtractor do
  let(:flowchart) { SpecSupport::LayoutParity::FlowchartRecognizer.new }
  let(:sequence) { SpecSupport::LayoutParity::SequenceRecognizer.new }
  let(:fixtures) { File.expand_path("../fixtures/layout_parity", __dir__) }
  let(:mermaid_dir) { File.expand_path("../fixtures_mermaid", __dir__) }
  let(:source_dir) { File.expand_path("../mermaid", __dir__) }

  def figure_of(file, recognizer)
    described_class.new(recognizer).extract(File.read(File.join(fixtures, file)))
  end

  def box_of(figure, key)
    figure.elements.find { |e| e.key == key }.bbox.to_a.map { |n| n.round(6) }
  end

  describe "nested transforms (contract section 2)" do
    {
      "translate then scale" => ["a", [20.0, 30.0, 40.0, 40.0]],
      "rotate(90) under a translate" => ["b", [6.0, 20.0, 10.0, 30.0]],
      "matrix on a circle" => ["c", [20.0, 30.0, 30.0, 50.0]]
    }.each do |name, (key, expected)|
      it "composes #{name}" do
        expect(box_of(figure_of("nested_transforms.svg", flowchart), key)).to eq(expected)
      end
    end

    it "composes a nested svg viewBox with meet" do
      expect(box_of(figure_of("nested_svg_viewport.svg", flowchart), "icon")).to eq([10.0, 10.0, 30.0, 20.0])
    end

    it "composes a nested svg viewBox with xMinYMin slice" do
      expect(box_of(figure_of("nested_svg_viewport.svg", flowchart), "slice")).to eq([0.0, 0.0, 40.0, 20.0])
    end

    it "rejects a transform function outside the contract" do
      svg = '<svg viewBox="0 0 9 9"><g class="node" id="flowchart-a-0" transform="skewX(5)"><rect width="1" height="1"/></g></svg>'
      expect { described_class.new(flowchart).extract(svg) }.to raise_error(ArgumentError, /skewX/)
    end
  end

  describe "scale and translation (contract section 2)" do
    it "reports numbers in viewBox units, ignoring the document width and height" do
      figure = figure_of("root_viewbox_offset.svg", flowchart)

      expect([box_of(figure, "a"), figure.root_box.to_a]).to eq([[110.0, 60.0, 130.0, 70.0], [100.0, 50.0, 300.0, 150.0]])
    end

    {
      "no viewBox falls back to width and height" => ['width="30" height="20"', [0.0, 0.0, 30.0, 20.0]],
      "percentage sizes leave the root user space unmapped" => ['width="100%" height="100%"', nil]
    }.each do |name, (attrs, expected)|
      it name do
        svg = %(<svg xmlns="http://www.w3.org/2000/svg" #{attrs}></svg>)

        expect(described_class.new(flowchart).extract(svg).root_box&.to_a).to eq(expected)
      end
    end

    it "keeps the max-width style as the fallback extent" do
      svg = '<svg width="100%" style="max-width: 400px;"></svg>'

      expect(described_class.new(flowchart).extract(svg).max_width).to eq(400.0)
    end
  end

  describe "text anchors (contract section 2)" do
    it "uses text x/y plus text and first tspan dx/dy, composed through transforms" do
      expect(box_of(figure_of("text_anchor.svg", flowchart), "t")).to eq([16.0, 21.0, 16.0, 21.0])
    end

    it "takes the position from the first positioned tspan when the text has none" do
      expect(box_of(figure_of("text_anchor.svg", flowchart), "u")).to eq([17.0, 18.0, 17.0, 18.0])
    end
  end

  describe "parents (contract section 1)" do
    it "records the smallest enclosing cluster, nothing at the root" do
      parents = figure_of("ancestry.svg", flowchart).elements.to_h { |e| [e.key, e.parent] }

      expect(parents).to eq("outer" => nil, "inner" => "outer", "deep" => "inner", "mid" => "outer", "free" => nil)
    end

    it "reads the nested subgraphs of a real mmdc reference" do
      svg = File.read(File.join(mermaid_dir, "flowchart/079_parser_should_handle_nested_subgraphs_3_74.svg"))
      parents = described_class.new(flowchart).extract(svg).elements.to_h { |e| [e.key, e.parent] }

      expect(parents).to eq("A" => nil, "B" => "A", "a" => "A", "b" => "A", "c" => "B")
    end

    it "gives a Sirena render the same parents" do
      source = "flowchart TD\n  subgraph B\n    c\n  end\n  a-->c\n  subgraph A\n    b-->B\n    a\n  end\n"
      parents = described_class.new(flowchart).extract(Sirena.render(source)).elements.to_h { |e| [e.key, e.parent] }

      expect(parents).to eq("A" => nil, "B" => "A", "a" => "A", "b" => "A", "c" => "B")
    end
  end

  describe "one code path for reference and Sirena" do
    it "gives a flowchart the same (kind, parent, key) set on both sides" do
      name = "001_config_0"
      reference = File.read(File.join(mermaid_dir, "flowchart/#{name}.svg"))
      sirena = Sirena.render(File.read(File.join(source_dir, "flowchart/#{name}.mmd")))
      keys = [reference, sirena].map { |svg| described_class.new(flowchart).extract(svg).keys.sort_by(&:last) }

      expected = %w[A B C D E F].map { |id| [:node, nil, id] }
      expect(keys).to eq([expected, expected])
    end

    it "gives a non-box type (sequence participants) the same keys on both sides, in viewBox units" do
      reference = File.read(File.join(mermaid_dir, "sequence/001_platform_knsv_0.svg"))
      sirena = Sirena.render("sequenceDiagram\n  Alice->>Bob: Hi\n")
      ref_figure = described_class.new(sequence).extract(reference)
      sirena_figure = described_class.new(sequence).extract(sirena)

      expect([ref_figure.keys.select { |k| k[0] == :"participant-top" }.sort_by(&:last), sirena_figure.keys.sort_by(&:last)])
        .to eq([[[:"participant-top", nil, "Alice"], [:"participant-top", nil, "Bob"]]] * 2)
    end

    it "separates a reference participant's top and bottom boxes" do
      reference = File.read(File.join(mermaid_dir, "sequence/001_platform_knsv_0.svg"))

      expect(described_class.new(sequence).extract(reference).keys.map(&:first).uniq.sort).to eq(%i[participant-bottom participant-top])
    end
  end
end
