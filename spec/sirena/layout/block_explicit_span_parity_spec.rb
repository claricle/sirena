# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Block do
  subject(:scene) { described_class.new.call(parser.parse(source)) }

  let(:parser) { Sirena::Parser::Block.new }

  context "with symmetric spans in one declared column" do
    let(:source) { fixture("a_node_with_a_square_shape_and_a_label-807b8b5c") }
    let(:reference_widths) do
      [18.828125, 45.65625, 72.484375, 99.3125,
       72.484375, 45.65625, 18.828125]
    end

    it "uses compact span widths and the reference row gap" do
      expect(symmetric_metrics)
        .to match([[27.0], Array.new(6, 8.0), be <= 0.15])
    end
  end

  context "when the final span exceeds the declared row" do
    let(:source) { fixture("block_spec-e162d2fc") }
    let(:reference_widths) { [222.15625, 337.234375, 107.078125, 222.15625] }

    it "keeps the overflowing span beside the preceding block" do
      expect(overflow_metrics)
        .to match([[0, 1, 2, 2], 8.0, be <= 0.15])
    end
  end

  def fixture(name)
    File.read("spec/mermaid/block/#{name}.mmd")
  end

  def nodes
    scene.children
  end

  def node(id)
    nodes.find { |candidate| candidate.id == id }
  end

  def vertical_gaps
    nodes.each_cons(2).map do |left, right|
      right.y - left.y - left.height
    end
  end

  def symmetric_metrics
    [nodes.map(&:height).uniq, vertical_gaps,
     maximum_relative_error(nodes.map(&:width), reference_widths)]
  end

  def row_signature
    rows = nodes.map(&:y).uniq.sort
    nodes.map { |item| rows.index(item.y) }
  end

  def horizontal_gap(left_id, right_id)
    left = node(left_id)
    node(right_id).x - left.x - left.width
  end

  def overflow_metrics
    ids = %w[fit overflow short also_overflow]
    widths = ids.map { |id| node(id).width }
    [row_signature, horizontal_gap("short", "also_overflow"),
     maximum_relative_error(widths, reference_widths)]
  end

  def maximum_relative_error(actual, reference)
    actual.zip(reference).map do |value, target|
      (value - target).abs / target
    end.max
  end
end
