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

  def summary(result, attribute = :key)
    pairs = result[:pairs].map { |pair| pair.map(&attribute) }
    [pairs, result[:ambiguous_count], result[:failures]]
  end

  def failure(type, key, count, reference_count, sirena_count)
    {
      type: type, group: [:node, nil, key], match_by: :id,
      count: count,
      reference_count: reference_count, sirena_count: sirena_count
    }
  end

  def scoped_elements(*parents)
    parents.map { |parent| element("same", parent: parent) }
  end

  def duplicate_elements(prefix)
    [element("same", label: "#{prefix} first"),
     element("same", label: "#{prefix} second")]
  end

  def failure_types(result)
    result[:failures].map { |entry| entry.values_at(:type, :group) }
  end

  it "matches semantic ids independently of source order" do
    result = match([element("a"), element("b")],
                   [element("b"), element("a")])

    expect(summary(result)).to eq([[["a", "a"], ["b", "b"]], 0, []])
  end

  it "uses labels when either side cannot expose a semantic id" do
    reference = element("reference-id", label: "Ready")
    sirena = element("Ready", label: "Ready", identity: :label)

    expect(match([reference], [sirena])[:pairs]).to eq([[reference, sirena]])
  end

  it "keeps equal keys in different parent scopes separate" do
    result = match(scoped_elements("outer", "inner"),
                   scoped_elements("inner", "outer"))

    expect(summary(result, :parent).first)
      .to eq([["outer", "outer"], ["inner", "inner"]])
  end

  it "pairs duplicate group members in source order and counts ambiguity" do
    result = match(duplicate_elements("reference"),
                   duplicate_elements("sirena"))

    expect(summary(result, :label))
      .to eq([[["reference first", "sirena first"],
               ["reference second", "sirena second"]], 2, []])
  end

  it "pairs common duplicate members and reports unequal group counts" do
    result = match([element("same"), element("same")], [element("same")])
    missing = failure(:missing, "same", 1, 2, 1)

    expect(summary(result)).to eq([[["same", "same"]], 1, [missing]])
  end

  it "reports missing and extra groups in their respective directions" do
    result = match([element("common"), element("missing")],
                   [element("common"), element("extra")])
    expected = [failure(:missing, "missing", 1, 1, 0),
                failure(:extra, "extra", 1, 0, 1)]

    expect(result[:failures]).to eq(expected)
  end

  it "never matches equal keys across element kinds" do
    result = match([element("same", kind: :node)],
                   [element("same", kind: :cluster)])
    failures = [[:missing, [:node, nil, "same"]],
                [:extra, [:cluster, nil, "same"]]]

    expect([result[:pairs], failure_types(result)]).to eq([[], failures])
  end
end
