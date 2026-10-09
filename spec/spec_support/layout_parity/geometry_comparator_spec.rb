# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::GeometryComparator do
  let(:box_class) { SpecSupport::LayoutParity::Bbox }
  let(:element_class) { SpecSupport::LayoutParity::Element }
  let(:figure_class) { SpecSupport::LayoutParity::Figure }

  def box(left, top, width, height)
    box_class.from_extent(left, top, width, height)
  end

  def element(key, extent)
    element_class.new(kind: :node, key: key, bbox: extent)
  end

  def pair(key, reference_extent, sirena_extent)
    [element(key, reference_extent), element(key, sirena_extent)]
  end

  def compare(pairs, root_box: box(0, 0, 100, 100), max_width: nil,
              ambiguous_count: 0)
    reference = figure_class.new(elements: pairs.map(&:first),
                                 root_box: root_box, max_width: max_width)
    described_class.compare(reference: reference, pairs: pairs,
                            ambiguous_count: ambiguous_count)
  end

  it "removes independent frame translations" do
    pairs = [pair("a", box(10, 20, 10, 10), box(110, 220, 10, 10)),
             pair("b", box(30, 40, 10, 10), box(130, 240, 10, 10))]

    expect(compare(pairs)[:worst_e_c]).to eq(0.0)
  end

  it "uses the reference frame diagonal for center error" do
    pairs = [pair("a", box(0, 0, 10, 10), box(0, 0, 10, 10)),
             pair("b", box(30, 40, 10, 10), box(70, 90, 10, 10))]

    expect(compare(pairs)[:worst_e_c]).to eq(1.0)
  end

  it "applies the width, height, and aspect equations exactly" do
    pairs = [pair("sized", box(0, 0, 10, 20), box(0, 0, 15, 10)),
             pair("frame", box(90, 90, 10, 10), box(90, 90, 10, 10))]
    result = compare(pairs)

    expect(result.values_at(:worst_e_w, :worst_e_h, :worst_e_a))
      .to eq([0.5, 0.5, 2.0])
  end

  context "with unequal width errors" do
    let(:pairs) do
      [pair("near", box(0, 0, 10, 10), box(0, 0, 11, 10)),
       pair("far", box(20, 0, 10, 10), box(20, 0, 20, 10))]
    end

    it "reports maxima and their keys rather than means" do
      result = compare(pairs, ambiguous_count: 3)

      summary = [result[:worst_e_w], result[:worst_keys][:e_w],
                 *result.values_at(:matched, :ambiguous)]
      expect(summary).to eq([1.0, [:node, nil, "far"], 2, 3])
    end
  end

  context "with six increasingly distorted pairs" do
    let(:pairs) do
      (1..6).map do |number|
        pair(number.to_s, box(number * 20, 0, 10, 10),
             box(number * 20, 0, number * 10, 10))
      end
    end
    let(:top_five) { compare(pairs)[:top5] }

    it "keeps the five worst pairs" do
      expect(top_five.map { |row| row[:key].last }).to eq(%w[6 5 4 3 2])
    end

    it "keeps evidence boxes for each pair" do
      expect(top_five.first.values_at(:bbox_reference, :bbox_sirena))
        .to eq([[120.0, 0.0, 130.0, 10.0], [120.0, 0.0, 180.0, 10.0]])
    end
  end

  it "skips a dimension only when both sides are zero" do
    result = compare([pair("line", box(0, 0, 0, 10), box(0, 0, 0, 20))])

    expect(result.values_at(:worst_e_w, :worst_e_h, :worst_e_a))
      .to eq([nil, 1.0, nil])
  end

  it "fails one-sided collapses" do
    result = compare([pair("collapsed", box(0, 0, 10, 10), box(0, 0, 0, 10))])

    expect(result.values_at(:worst_e_w, :worst_e_a))
      .to eq([1.0, Float::INFINITY])
  end

  it "uses the root extent for a degenerate matched frame" do
    result = compare([pair("anchor", box(10, 10, 0, 0),
                           box(13, 14, 0, 0))],
                     root_box: box(0, 0, 30, 40))

    expect(result[:worst_e_c]).to eq(0.1)
  end

  it "falls back from a missing root extent to max-width as the diagonal" do
    result = compare([pair("anchor", box(0, 0, 0, 0),
                           box(40, 0, 0, 0))],
                     root_box: nil, max_width: 400)

    expect(result[:worst_e_c]).to eq(0.1)
  end

  it "fails explicitly when a degenerate frame has no reference extent" do
    action = lambda do
      compare([pair("anchor", box(0, 0, 0, 0), box(1, 0, 0, 0))],
              root_box: nil)
    end

    expect(&action).to raise_error(ArgumentError, /no root extent/)
  end
end
