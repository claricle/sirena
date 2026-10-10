# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Requirement do
  subject(:renderer) { described_class.new }

  def scene_for(source)
    diagram = Sirena::Parser::Requirement.new.parse(source)
    Sirena::Layout::Requirement.new.call(diagram)
  end

  def texts(scene)
    renderer.render(scene).to_xml.scan(%r{>([^<>]+)</text>}).flatten
  end

  let(:source) do
    <<~MERMAID
      requirementDiagram
        requirement test_req {
          id: 1
          text: the test text.
          risk: high
          verifymethod: test
        }
        element test_entity {
          type: simulation
          docref: test_ref
        }
        test_entity - satisfies -> test_req
    MERMAID
  end
  let(:scene) { scene_for(source) }

  it "renders typed requirements, elements, relationships, and canvas" do
    expect(rendered_scene_evidence)
      .to match([Sirena::Svg::Document, Sirena::Layout::Requirement::Scene,
                 %w[element-test_entity relationship-test_entity-test_req
                    requirement-test_req], include("#ff6b6b"),
                 [scene.width, scene.height, scene.view_box]])
  end

  it "draws the same requirement and element property text" do
    expect(property_text_evidence).to eq([true, true])
  end

  it "omits a Doc Ref label when none was declared" do
    without_docref = source.sub(/\s+docref: test_ref\n/, "\n")
    expect(texts(scene_for(without_docref)).grep(/Doc Ref/)).to be_empty
  end

  it "renders an explicit empty typed Scene" do
    svg = renderer.render(empty_scene)
    expect([svg.width, svg.height, svg.to_xml.include?("<g")])
      .to eq([400, 300, false])
  end

  it "renders multiple requirements" do
    expect(multiple_requirements_xml.scan('id="requirement-').size).to eq(2)
  end

  described_class::REQUIREMENT_TYPE_LABELS.each do |type, label|
    it "labels #{type} as <<#{label}>>" do
      source = <<~MERMAID
        requirementDiagram
          #{type} need {
          }
      MERMAID
      expect(texts(scene_for(source))).to include("&lt;&lt;#{label}&gt;&gt;")
    end
  end

  it "keeps the risk palettes public" do
    expect(described_class::RISK_COLORS)
      .to include("high" => "#ff6b6b", "medium" => "#ffd93d",
                  "low" => "#6bcf7f")
  end

  def rendered_scene_evidence
    svg = renderer.render(scene)
    xml = svg.to_xml
    [svg.class, scene.class, scene_ids(xml), stroke_colors(xml),
     [svg.width, svg.height, svg.view_box]]
  end

  def scene_ids(xml)
    ids = %w[
      requirement-test_req
      element-test_entity
      relationship-test_entity-test_req
    ]
    pattern = /id="(#{Regexp.union(ids)})"/
    xml.scan(pattern).flatten.sort
  end

  def stroke_colors(xml)
    xml.scan(/stroke="(#[a-f0-9]+)"/).flatten
  end

  def property_text_evidence
    rendered_texts = texts(scene)
    expected = [
      "&lt;&lt;Requirement&gt;&gt;", "&lt;&lt;Element&gt;&gt;",
      "Text: the test text.", "Risk: High", "Verification: Test",
      "Type: simulation", "Doc Ref: test_ref", "&lt;&lt;satisfies&gt;&gt;"
    ]
    [expected.all? { |text| rendered_texts.include?(text) },
     rendered_texts.each_cons(2).include?(["Type: simulation",
                                           "Doc Ref: test_ref"])]
  end

  def empty_scene
    Sirena::Layout::Requirement::Scene.new(
      width: 400, height: 300, view_box: "0 0 400 300",
    )
  end

  def multiple_requirements_xml
    source = <<~MERMAID
      requirementDiagram
        functionalRequirement req1 {
          id: 1
        }
        performanceRequirement req2 {
          id: 2
        }
    MERMAID
    renderer.render(scene_for(source)).to_xml
  end
end
