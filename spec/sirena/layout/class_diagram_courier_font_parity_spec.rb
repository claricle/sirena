# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  let(:widths) do
    lambda do |name|
      path = File.expand_path("../../mermaid/unknown/#{name}.mmd", __dir__)
      parsed = Sirena::Notation::Mermaid.parse(File.read(path))
      described_class.new.call(parsed.diagram).children
        .to_h { |node| [node.id, node.width.round(2)] }
    end
  end

  # Pinned mmdc reference boxes: Courier New is 1229/2048 em per glyph.
  it "sizes a courier class box from its widest member like mmdc" do
    expect(widths.call("class-a6d2ad68")["BankAccount"])
      .to be_within(0.05).of(316.86)
  end

  it "sizes courier class names like mmdc" do
    expect(widths.call("class-2f76a319").values.uniq).to eq([81.61])
  end

  it "keeps Trebuchet widths without a font family" do
    source = "classDiagram\nclass classA\n"
    parsed = Sirena::Notation::Mermaid.parse(source)
    width = described_class.new.call(parsed.diagram).children.first.width
    expect(width.round(2)).to eq(69.28)
  end
end
