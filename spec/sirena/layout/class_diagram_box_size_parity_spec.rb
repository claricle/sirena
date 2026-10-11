# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  subject(:nodes) do
    diagram = Sirena::Parser::ClassDiagram.new.parse(source)
    described_class.new.call(diagram).children.to_h { [_1.id, _1] }
  end

  {
    "no members" => ["", 84.0],
    "one attribute" => ["+a", 120.0],
    "two attributes" => ["+a\n+b", 144.0],
    "one method" => ["+m()", 126.0],
    "three methods" => ["+m()\n+n()\n+o()", 174.0],
    "an attribute and a method" => ["+a\n+m()", 144.0],
    "two of each" => ["+a\n+b\n+m()\n+n()", 192.0],
    "a stereotype alone" => ["<<interface>>", 108.0],
  }.each do |label, (rows, height)|
    context "with #{label}" do
      let(:source) { "classDiagram\nclass A {\n#{rows}\n}\nclass B\n" }

      it "sizes the box to the mmdc height" do
        expect(nodes.fetch("A").height).to eq(height)
      end
    end
  end

  context "with a generic class name" do
    let(:source) { "classDiagram\nclass Car~T~\n" }

    it "sizes the box from the displayed angle brackets" do
      expect(nodes.fetch("Car").width).to be_within(0.5).of(77.6875)
    end
  end

  context "with a short name beside a long one" do
    let(:source) { "classDiagram\nclass Ab\nclass Abcdefghijklmnop\n" }

    it "sizes each box to its own name, without a minimum width" do
      widths = nodes.values.map(&:width)
      expect(widths.first).to be < widths.last / 2
    end
  end

  context "with a box wider than a grid cell" do
    let(:source) { "classDiagram\nclass #{'W' * 40}\nclass B\n" }

    it "starts the next class past it instead of overlapping" do
      first, second = nodes.values
      expect(second.x).to be >= first.x + first.width
    end
  end
end
