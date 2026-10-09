# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Requirement do
  def requirement(**attributes)
    Sirena::Diagram::RequirementNode.new({ name: "need" }.merge(attributes))
  end

  def element(**attributes)
    Sirena::Diagram::RequirementElement.new({ name: "part" }.merge(attributes))
  end

  def positioned(item, x_position: 10, y_position: 20, width: 180, height: 120)
    {
      requirement: item,
      x: x_position,
      y: y_position,
      width: width,
      height: height,
    }
  end

  def positioned_element(item)
    { element: item, x: 220, y: 20, width: 160, height: 100 }
  end

  let(:renderer) { described_class.new(theme: Sirena::Theme.new) }
  let(:empty_svg) { renderer.render({}) }
  let(:fallback_xml) do
    item = requirement(type: "customNeed", risk: "surprising")
    renderer.render(
      width: 400,
      height: 180,
      requirements: { "need" => positioned(item) },
      elements: { "part" => positioned_element(element) },
    ).to_xml
  end
  let(:relationships) do
    [
      {
        source: "part", target: "need", type: "satisfies",
        from_x: 300, from_y: 120, to_x: 100, to_y: 140
      },
      {
        source: nil, target: nil,
        from_x: 20, from_y: 160, to_x: 180, to_y: 160
      },
    ]
  end
  let(:relationships_xml) do
    renderer.render(
      width: 400, height: 200, relationships: relationships,
    ).to_xml
  end

  it "uses the default canvas when sections are absent" do
    expect(empty_svg).to have_attributes(width: 800.0, height: 600.0)
  end

  it "leaves the default canvas empty" do
    expect(empty_svg.to_xml).not_to match(/<(?:g|text|rect|path|polygon)\b/)
  end

  it "falls back for an unknown requirement type" do
    expect(fallback_xml).to include("&lt;&lt;customNeed&gt;&gt;", 'stroke="#666"')
  end

  it "title-cases an unknown risk" do
    expect(fallback_xml).to include("Risk: Surprising")
  end

  it "uses the element fallback type" do
    expect(fallback_xml).to include("&lt;&lt;Element&gt;&gt;")
  end

  it "omits absent optional properties" do
    pattern = />(?:ID|Text|Verification|Type|Doc Ref):/
    expect(fallback_xml).not_to match(pattern)
  end

  it "identifies relationships with named endpoints" do
    expect(relationships_xml).to include('id="relationship-part-need"')
  end

  it "identifies relationships with missing endpoints" do
    expect(relationships_xml).to include('id="relationship--"')
  end

  it "labels typed relationships" do
    expect(relationships_xml).to include("&lt;&lt;satisfies&gt;&gt;")
  end

  it "draws each relationship path" do
    expect(relationships_xml.scan("<path").size).to eq(2)
  end

  it "draws each relationship head" do
    expect(relationships_xml.scan("<polygon").size).to eq(2)
  end
end
