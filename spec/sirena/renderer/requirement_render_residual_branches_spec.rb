# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Requirement, "#render" do
  let(:source) do
    <<~MERMAID
      requirementDiagram
        requirement r {
          id: 1
          text: t
          risk: high
          verifymethod: test
        }
        element e {
          type: simulation
        }
        e - satisfies -> r
    MERMAID
  end
  let(:scene) do
    diagram = Sirena::Parser::Requirement.new.parse(source)
    Sirena::Layout::Requirement.new.call(diagram)
  end
  let(:xml) { described_class.new.render(scene).to_xml }

  it "labels a relationship" do
    expect(xml).to include("satisfies")
  end

  it "renders an unlabelled relationship without its label" do
    scene.edges.first.labels = []

    expect(xml).not_to include("satisfies")
  end
end
