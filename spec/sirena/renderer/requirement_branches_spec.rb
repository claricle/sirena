# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Requirement do
  def requirement(**attributes)
    Sirena::Diagram::RequirementNode.new({ name: "need" }.merge(attributes))
  end

  def element(**attributes)
    Sirena::Diagram::RequirementElement.new({ name: "part" }.merge(attributes))
  end

  def positioned(item, x: 10, y: 20, width: 180, height: 120)
    { requirement: item, x: x, y: y, width: width, height: height }
  end

  def positioned_element(item)
    { element: item, x: 220, y: 20, width: 160, height: 100 }
  end

  let(:renderer) { described_class.new(theme: Sirena::Theme.new) }

  it "uses the default canvas when sections are absent" do
    svg = renderer.render({})

    expect(svg).to have_attributes(width: 800.0, height: 600.0)
    expect(svg.to_xml).not_to match(/<(?:g|text|rect|path|polygon)\b/)
  end

  it "omits absent optional properties and falls back for unknown values" do
    item = requirement(type: "customNeed", risk: "surprising")
    part = element
    xml = renderer.render(
      width: 400,
      height: 180,
      requirements: { "need" => positioned(item) },
      elements: { "part" => positioned_element(part) },
    ).to_xml

    expect(xml).to include("&lt;&lt;customNeed&gt;&gt;", 'stroke="#666"')
    expect(xml).to include("Risk: Surprising")
    expect(xml).to include("&lt;&lt;Element&gt;&gt;")
    expect(xml).not_to match(/>(?:ID|Text|Verification|Type|Doc Ref):/)
  end

  it "renders labelled and unlabelled relationships with named or missing endpoints" do
    relationships = [
      {
        source: "part", target: "need", type: "satisfies",
        from_x: 300, from_y: 120, to_x: 100, to_y: 140
      },
      {
        source: nil, target: nil,
        from_x: 20, from_y: 160, to_x: 180, to_y: 160
      },
    ]
    xml = renderer.render(width: 400, height: 200,
                          relationships: relationships).to_xml

    expect(xml).to include('id="relationship-part-need"')
    expect(xml).to include('id="relationship--"')
    expect(xml).to include("&lt;&lt;satisfies&gt;&gt;")
    expect(xml.scan("<path").size).to eq(2)
    expect(xml.scan("<polygon").size).to eq(2)
  end
end
