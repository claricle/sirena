# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::ElementMatcher do
  let(:element_class) { SpecSupport::LayoutParity::Element }
  let(:figure_class) { SpecSupport::LayoutParity::Figure }

  def element(key, kind: :node, parent: nil, label: key, identity: :id)
    element_class.new(kind: kind, key: key, bbox: nil, label: label,
                      identity: identity).with_parent(parent)
  end

  def figure(*elements)
    figure_class.new(elements: elements, root_box: nil)
  end

  def match(reference_elements, sirena_elements)
    described_class.match(reference: figure(*reference_elements),
                          sirena: figure(*sirena_elements))
  end

  def pair_keys(result)
    result[:pairs].map { |pair| pair.map(&:key) }
  end

  it "matches semantic ids independently of source order" do
    result = match([element("a"), element("b")],
                   [element("b"), element("a")])

    expect(pair_keys(result)).to eq([["a", "a"], ["b", "b"]])
    expect(result.values_at(:ambiguous_count, :failures)).to eq([0, []])
  end

  it "uses labels when either side cannot expose a semantic id" do
    reference = element("reference-id", label: "Ready")
    sirena = element("Ready", label: "Ready", identity: :label)

    expect(match([reference], [sirena])[:pairs]).to eq([[reference, sirena]])
  end

  it "keeps equal keys in different parent scopes separate" do
    outer = element("same", parent: "outer")
    inner = element("same", parent: "inner")
    result = match([outer, inner],
                   [element("same", parent: "inner"),
                    element("same", parent: "outer")])

    expect(result[:pairs].map { |left, right| [left.parent, right.parent] })
      .to eq([["outer", "outer"], ["inner", "inner"]])
  end

  it "pairs duplicate group members in source order and counts ambiguity" do
    reference = [element("same", label: "reference first"),
                 element("same", label: "reference second")]
    sirena = [element("same", label: "sirena first"),
              element("same", label: "sirena second")]
    result = match(reference, sirena)

    expect(result[:pairs].map { |pair| pair.map(&:label) })
      .to eq([["reference first", "sirena first"],
              ["reference second", "sirena second"]])
    expect(result[:ambiguous_count]).to eq(2)
  end

  it "pairs common duplicate members and reports unequal group counts" do
    result = match([element("same"), element("same")], [element("same")])

    expect(pair_keys(result)).to eq([["same", "same"]])
    expect(result[:ambiguous_count]).to eq(1)
    expect(result[:failures]).to eq(
      [
        {
          type: :missing,
          group: [:node, nil, "same"],
          match_by: :id,
          count: 1,
          reference_count: 2,
          sirena_count: 1,
        },
      ],
    )
  end

  it "reports missing and extra groups in their respective directions" do
    result = match([element("common"), element("missing")],
                   [element("common"), element("extra")])

    expect(result[:failures]).to eq(
      [
        {
          type: :missing,
          group: [:node, nil, "missing"],
          match_by: :id,
          count: 1,
          reference_count: 1,
          sirena_count: 0,
        },
        {
          type: :extra,
          group: [:node, nil, "extra"],
          match_by: :id,
          count: 1,
          reference_count: 0,
          sirena_count: 1,
        },
      ],
    )
  end

  it "never matches equal keys across element kinds" do
    result = match([element("same", kind: :node)],
                   [element("same", kind: :cluster)])

    expect(result[:pairs]).to be_empty
    expect(result[:failures].map { |failure| failure.values_at(:type, :group) })
      .to eq([[:missing, [:node, nil, "same"]],
              [:extra, [:cluster, nil, "same"]]])
  end
end
