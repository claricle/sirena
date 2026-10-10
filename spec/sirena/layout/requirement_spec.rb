# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/requirement"

RSpec.describe Sirena::Layout::Requirement do
  let(:source) do
    <<~MERMAID
      requirementDiagram
        accTitle: Accessible requirements
        accDescr: Requirement relationships
        functionalRequirement signed_events:::critical,audited {
          id: REQ-1
          text: Accept all correctly signed event messages
          risk: high
          verifymethod: test
        }
        element gateway:::external {
          type: service
          docref: ARCH-4
        }
        gateway - satisfies -> signed_events
        style signed_events fill:#fee,stroke:#900,stroke-width:3px
        classDef critical fill:#fdd,stroke:#800,stroke-width:2px
        class signed_events critical,audited
    MERMAID
  end
  let(:diagram) { Sirena::Parser::Requirement.new.parse(source) }
  let(:graph) do
    Sirena::Notation::Mermaid::IRAdapters::Requirement.call(diagram)
  end

  it "lays out direct graph IR byte-identically to the private diagram" do
    layout = described_class.new
    private_scene = layout.call(diagram)
    shared_scene = layout.call(graph)

    expect(Marshal.dump(shared_scene)).to eq(Marshal.dump(private_scene))
  end

  it "retains requirement, element, and relationship content through IR" do
    scene = described_class.new.call(graph)
    expect(scene_signature(scene)).to eq(expected_scene_signature)
  end

  def scene_signature(scene)
    requirement = scene.children.find { |node| node.kind == "requirement" }
    element = scene.children.find { |node| node.kind == "element" }
    [requirement.id, requirement.risk, element.id,
     matching_labels(requirement, element), relationship_signature(scene)]
  end

  def matching_labels(requirement, element)
    labels = (requirement.labels + element.labels).map(&:text)
    expected_scene_labels.select { |label| labels.include?(label) }
  end

  def expected_scene_labels
    [
      "<<Functional Requirement>>", "ID: REQ-1", "Risk: High",
      "Verification: Test", "Type: service", "Doc Ref: ARCH-4"
    ]
  end

  def relationship_signature(scene)
    scene.edges.map do |edge|
      [edge.source, edge.target, edge.labels.first&.text]
    end
  end

  def expected_scene_signature
    ["signed_events", "high", "gateway", expected_scene_labels,
     [["gateway", "signed_events", "<<satisfies>>"]]]
  end
end
