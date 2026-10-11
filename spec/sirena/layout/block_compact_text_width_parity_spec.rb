# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Block do
  subject(:scene) { described_class.new.call(parser.parse(source)) }

  let(:parser) { Sirena::Parser::Block.new }

  context "with automatically sized compact leaves" do
    let(:source) { fixture("a_diagram_with_a_node-6f1beb92") }

    it "measures their width at Mermaid's browser font size" do
      expect(relative_width_error([21.484375])).to be <= 0.05
    end

    it "keeps their compact height" do
      expect(scene.children.map(&:height)).to eq([27.0])
    end
  end

  context "with an automatically sized compact row" do
    let(:source) { fixture("block_spec-e104ba37") }

    it "matches the browser widths" do
      expect(relative_width_error([16.921875, 16.921875])).to be <= 0.002
    end

    it "keeps the compact gap" do
      left, right = scene.children
      expect(right.x - left.x - left.width).to eq(8.0)
    end
  end

  context "with compact spans in multiple declared columns" do
    let(:source) { fixture("block_spec-e162d2fc") }

    it "derives every span from the browser-measured column width" do
      reference = [222.15625, 337.234375, 107.078125, 222.15625]

      expect(relative_width_error(reference)).to be <= 0.012
    end
  end

  context "with proportional spans in one declared column" do
    let(:source) do
      fixture("a_node_with_a_square_shape_and_a_label-807b8b5c")
    end

    it "retains the single-column text-width rule" do
      reference = [18.828125, 45.65625, 72.484375, 99.3125,
                   72.484375, 45.65625, 18.828125]

      expect(relative_width_error(reference)).to be <= 0.004
    end
  end

  def fixture(name)
    File.read("spec/mermaid/block/#{name}.mmd")
  end

  def relative_width_error(reference)
    scene.children.map(&:width).zip(reference).map do |actual, expected|
      (actual - expected).abs / expected
    end.max
  end
end
