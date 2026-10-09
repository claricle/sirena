# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::SpatialInvariantChecker do
  let(:box_class) { SpecSupport::LayoutParity::Bbox }
  let(:element_class) { SpecSupport::LayoutParity::Element }
  let(:fixtures) do
    {
      missing_pairs: [
        pair("parent", box(0, 0, 20, 20), box(0, 0, 5, 5)),
        pair("child", box(5, 5, 5, 5), box(20, 20, 5, 5)),
      ],
      missing_evidence: {
        rule: "missing-reference-containment",
        subject_keys: [[[:node, nil, "parent"], 0],
                       [[:node, nil, "child"], 0]],
        expected: true,
        actual: false,
        bbox_reference: [[0.0, 0.0, 20.0, 20.0],
                         [5.0, 5.0, 10.0, 10.0]],
        bbox_sirena: [[0.0, 0.0, 5.0, 5.0],
                      [20.0, 20.0, 25.0, 25.0]],
      },
      introduced_pairs: [
        pair("peer-a", box(0, 0, 5, 5), box(0, 0, 20, 20)),
        pair("peer-b", box(10, 10, 5, 5), box(5, 5, 5, 5)),
      ],
      introduced_summary: [
        %w[unexpected-sirena-containment peer-overlap],
        [[[:node, nil, "peer-a"], 0], [[:node, nil, "peer-b"], 0]],
      ],
      overlapping_pairs: [
        pair("left", box(0, 0, 4, 4), box(0, 0, 4, 4)),
        pair("right", box(10, 10, 4, 4), box(3, 2, 4, 4)),
      ],
      overlap_evidence: {
        rule: "peer-overlap",
        normalized: {
          intersection_width: 1.0,
          intersection_height: 2.0,
          threshold: 0.5,
        },
      },
      boundary_groups: [
        [
          pair("a", box(0, 0, 1, 1), box(0, 0, 2, 2)),
          pair("b", box(5, 5, 1, 1), box(2, 0, 2, 2)),
        ],
        [
          pair("a", box(0, 0, 1, 1), box(0, 0, 2, 2)),
          pair("b", box(5, 5, 1, 1), box(1.5, 0, 2, 2)),
        ],
      ],
      ancestry_pairs: [
        pair("outer", box(0, 0, 30, 30), box(0, 0, 30, 30)),
        pair("middle", box(5, 5, 20, 20), box(2, 2, 25, 25)),
        pair("leaf", box(10, 10, 5, 5), box(4, 4, 20, 20)),
      ],
      duplicate_pairs: [
        pair("same", box(0, 0, 2, 2), box(0, 0, 3, 3)),
        pair("same", box(10, 10, 2, 2), box(2, 2, 3, 3)),
      ],
      duplicate_keys: [
        [[:node, nil, "same"], 0],
        [[:node, nil, "same"], 1],
      ],
    }
  end

  def box(origin_x, origin_y, width, height)
    box_class.from_extent(origin_x, origin_y, width, height)
  end

  def element(key, extent)
    element_class.new(kind: :node, key: key, bbox: extent)
  end

  def pair(key, reference_extent, sirena_extent)
    [element(key, reference_extent), element(key, sirena_extent)]
  end

  def check(*pairs)
    described_class.check(pairs: pairs)
  end

  it "allows preserved ancestor containment" do
    failures = check(
      pair("parent", box(0, 0, 20, 20), box(5, 5, 30, 30)),
      pair("child", box(5, 5, 5, 5), box(10, 10, 10, 10)),
    )

    expect(failures).to be_empty
  end

  it "reports reference containment lost by Sirena" do
    failures = check(*fixtures.fetch(:missing_pairs))

    expect(failures.first).to include(fixtures.fetch(:missing_evidence))
  end

  it "reports containment introduced only by Sirena" do
    failures = check(*fixtures.fetch(:introduced_pairs))
    actual = [failures.map { |failure| failure[:rule] },
              failures.first[:subject_keys]]

    expect(actual).to eq(fixtures.fetch(:introduced_summary))
  end

  it "reports peer intersection above the threshold on both axes" do
    failures = check(*fixtures.fetch(:overlapping_pairs))

    expect(failures)
      .to contain_exactly(include(fixtures.fetch(:overlap_evidence)))
  end

  it "allows touching and overlap of exactly half a unit" do
    failures = fixtures.fetch(:boundary_groups)
      .flat_map { |pairs| check(*pairs) }

    expect(failures).to be_empty
  end

  it "allows overlap above the threshold on only one axis" do
    failures = check(
      pair("a", box(0, 0, 1, 1), box(0, 0, 4, 4)),
      pair("b", box(10, 10, 1, 1), box(2, 3.75, 4, 4)),
    )

    expect(failures).to be_empty
  end

  it "uses reference ancestry even when ancestor boxes overlap deeply" do
    failures = check(*fixtures.fetch(:ancestry_pairs))

    expect(failures).to be_empty
  end

  it "distinguishes duplicate identities with stable source ordinals" do
    failures = check(*fixtures.fetch(:duplicate_pairs))

    expect(failures.first[:subject_keys])
      .to eq(fixtures.fetch(:duplicate_keys))
  end
end
