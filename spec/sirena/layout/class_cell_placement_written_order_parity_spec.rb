# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassCellPlacement do
  let(:parse) { ->(text) { Sirena::Parser::ClassDiagram.new.parse(text) } }
  let(:tops) do
    lambda do |text|
      scene = Sirena::Layout::ClassDiagram.new.call(parse.call(text))
      scene.children.to_h { |node| [node.id, node.y] }
    end
  end

  it "flags a left-pointing relation as written in reverse" do
    flags = ["A <|-- B", "A --|> B"].map do |line|
      parse.call("classDiagram\n#{line}\n").relationships.first
        .written_reversed
    end
    expect(flags).to eq([true, nil])
  end

  context "with a left-pointing fan (corpus class-2a7c1e3c)" do
    let(:source) do
      File.read(File.expand_path(
                  "../../mermaid/class_diagram/class-2a7c1e3c.mmd", __dir__
                ))
    end

    it "ranks the written-first class above all three children" do
      y = tops.call(source)
      expect(y.values_at("Duck", "Fish", "Zebra").map { _1 > y["Animal"] })
        .to eq([true, true, true])
    end

    it "puts the three children in one rank, as mmdc does" do
      expect(tops.call(source).values_at("Duck", "Fish", "Zebra").uniq.size)
        .to eq(1)
    end
  end

  it "puts the written-first class on top of a `<--` pair" do
    y = tops.call("classDiagram\nA <-- B\n")
    expect(y.fetch("A")).to be < y.fetch("B")
  end
end
