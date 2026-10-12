# frozen_string_literal: true

# mmdc breaks an edge label wider than 200px at spaces into a 200px box of
# 24px lines, keeping the space after a word on its line (fourteen words
# take four lines, not three), and dagre places a labelled edge through a
# stand-in as wide as the label across the flow. Sizes and centres are
# read off mmdc SVGs; a centre here is mmdc's less its 8px margin.
RSpec.describe Sirena::Layout::Flowchart do
  describe "an edge label's box" do
    subject(:box) do
      source = "graph TD\n  A -->|#{text}| B"
      model = Sirena::Parser::Flowchart.new.parse(source)
      label = described_class.new.to_graph(model).edges.first.labels.first
      [label.width, label.height / 16.0]
    end

    {
      "This is the 123 s text" => [149.1, 1],
      "text including graph space and v" => [200.0, 2],
      "one two three four five six seven eight nine ten eleven twelve " \
      "thirteen fourteen" => [200.0, 4],
      "Supercalifragilisticexpialidociouslylongwordwithoutanyspaces" =>
        [440.8, 1],
    }.each do |label_text, (width, lines)|
      context "with #{label_text.inspect}" do
        let(:text) { label_text }

        it "is #{width} wide over #{lines} line(s), as mmdc" do
          expect(box).to match([be_within(0.5).of(width), lines])
        end
      end
    end
  end

  it "opens a wrapped label's two lines between its nodes, as mmdc" do
    model = Sirena::Parser::Flowchart.new
      .parse("graph TD;A-- text including graph space and v --xB[blav]")
    nodes = described_class.new.to_graph(model).children
    middles = nodes.map { |node| node.y + (node.height / 2.0) }

    expect(middles).to eq([35.0, 187.0])
  end

  # `A --> B` and `A -->|a fairly long edge label here| C`, a level as
  # DirectedPlacement hands it over: turned on its side for LR, where both
  # edges carry the fourteen-word label.
  describe described_class::RowCentering do
    subject(:centres) do
      described_class.apply(level, label_axis: label_axis)
      level[:children].to_h { |box| [box[:id], box[:x] + (box[:width] / 2.0)] }
    end

    let(:sizes) { { "A" => 69.44, "B" => 69.056, "C" => 69.568 } }
    let(:label) { { width: 200.0, height: 32.0 } }
    let(:first_labels) { [] }
    let(:level) do
      rows = { "A" => [0.0, 0.0], "B" => [0.0, 100.0], "C" => [100.0, 100.0] }
      {
        children: rows.map do |id, (x, y)|
          { id: id, x: x, y: y, width: sizes[id], height: 54.0 }
        end,
        edges: [
          { sources: ["A"], targets: ["B"], labels: first_labels },
          { sources: ["A"], targets: ["C"], labels: [label] },
        ],
      }
    end

    context "with a downward level" do
      let(:label_axis) { :height }

      it "spaces the fan by the label's width" do
        expect(centres.values_at("A", "B", "C"))
          .to match([be_within(0.01).of(94.53), be_within(0.01).of(34.53),
                     be_within(0.01).of(154.53)])
      end
    end

    context "with a turned level" do
      let(:label_axis) { :width }
      let(:sizes) { { "A" => 54.0, "B" => 54.0, "C" => 54.0 } }
      let(:label) { { width: 200.0, height: 64.0 } }
      let(:first_labels) { [label] }

      it "spaces the fan by the labels' line boxes" do
        b = centres["B"]

        expect([centres["A"] - b, centres["C"] - b]).to eq([58.0, 116.0])
      end
    end

    # Only centred, as before labelled edges reached Brandes-Koepf.
    context "without a label axis" do
      let(:label_axis) { nil }

      it "centres the rows and leaves the label out" do
        expect(centres.values_at("A", "B", "C"))
          .to match([be_within(0.01).of(84.78), be_within(0.01).of(34.53),
                     be_within(0.01).of(134.78)])
      end
    end
  end
end
