# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Requirement do
  subject(:renderer) { described_class.new(theme: Sirena::Theme.new) }

  def diagram(requirements: [], elements: [], relationships: [])
    Sirena::Diagram::Requirement.new(
      requirements: requirements, elements: elements,
      relationships: relationships
    )
  end

  def requirement(**attributes)
    Sirena::Diagram::RequirementNode.new({ name: "need" }.merge(attributes))
  end

  def element(**attributes)
    Sirena::Diagram::RequirementElement.new({ name: "part" }.merge(attributes))
  end

  def relationship(**attributes)
    Sirena::Diagram::RequirementRelationship.new(attributes)
  end

  it "uses an explicit typed empty canvas without drawing sections" do
    svg = renderer.render(empty_scene)
    contains_drawing = svg.to_xml.match?(/<(?:g|text|rect|path|polygon)\b/)
    expect([svg.width, svg.height, contains_drawing]).to eq([800, 600, false])
  end

  it "falls back for an unknown type and risk while title-casing the risk" do
    evidence = xml_evidence(unknown_requirement_xml,
                            "&lt;&lt;customNeed&gt;&gt;", "Risk: Surprising",
                            'stroke="#666"')
    expect(evidence).to eq([true, true, true])
  end

  it "emits the element fallback stereotype without absent properties" do
    xml = bare_element_xml
    evidence = [xml.include?("&lt;&lt;Element&gt;&gt;"),
                xml.match?(/>(?:ID|Text|Verification|Type|Doc Ref):/)]
    expect(evidence).to eq([true, false])
  end

  it "keeps only relationships whose named endpoints resolve" do
    expect(filtered_scene.edges.map { |edge| [edge.source, edge.target] })
      .to eq([%w[part need]])
  end

  it "renders each typed relationship path, label, and head" do
    xml = rendered_relationship_xml
    evidence = xml_evidence(xml, 'id="relationship-part-need"',
                            "&lt;&lt;satisfies&gt;&gt;")
    expect([*evidence, xml.scan("<path").size, xml.scan("<polygon").size])
      .to eq([true, true, 1, 2])
  end

  def empty_scene
    Sirena::Layout::Requirement::Scene.new(
      width: 800, height: 600, view_box: "0 0 800 600",
    )
  end

  def unknown_requirement_xml
    scene = Sirena::Layout::Requirement.new.call(
      diagram(requirements: [requirement(type: "customNeed",
                                         risk: "surprising")]),
    )
    renderer.render(scene).to_xml
  end

  def bare_element_xml
    scene = Sirena::Layout::Requirement.new.call(
      diagram(elements: [element]),
    )
    renderer.render(scene).to_xml
  end

  def filtered_scene
    relations = [
      relationship(source: "part", target: "need", type: "satisfies"),
      relationship(source: "missing", target: "need", type: "verifies"),
    ]
    Sirena::Layout::Requirement.new.call(
      diagram(requirements: [requirement], elements: [element],
              relationships: relations),
    )
  end

  def rendered_relationship_xml
    relation = relationship(
      source: "part", target: "need", type: "satisfies",
    )
    scene = Sirena::Layout::Requirement.new.call(
      diagram(requirements: [requirement], elements: [element],
              relationships: [relation]),
    )
    renderer.render(scene).to_xml
  end

  def xml_evidence(xml, *fragments)
    fragments.map { |fragment| xml.include?(fragment) }
  end
end
