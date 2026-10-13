# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Requirement Integration", :aggregate_failures do
  describe "complete requirement pipeline" do
    let(:diagram) { Sirena::Parser::Requirement.new.parse(source) }
    let(:scene) { Sirena::Layout::Requirement.new.call(diagram) }
    let(:svg) { Sirena::Renderer::Requirement.new.render(scene) }

    context "with a simple requirement diagram" do
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
              }

              test_entity - satisfies -> test_req
        MERMAID
      end

      it "parses the requirement, element and relationship" do
        expect(diagram).to be_a(Sirena::Diagram::Requirement)
        expect(diagram.requirements.length).to eq(1)
        expect(diagram.elements.length).to eq(1)
        expect(diagram.relationships.length).to eq(1)
      end

      it "parses the requirement's fields" do
        req = diagram.requirements.first

        expect([req.name, req.id, req.text, req.risk, req.verifymethod])
          .to eq(["test_req", "1", "the test text.", "high", "test"])
      end

      it "parses the element's fields" do
        elem = diagram.elements.first

        expect([elem.name, elem.type]).to eq(%w[test_entity simulation])
      end

      it "parses the relationship's fields" do
        rel = diagram.relationships.first

        expect([rel.source, rel.target, rel.type])
          .to eq(%w[test_entity test_req satisfies])
      end

      it "transforms to a Scene with one node of each kind" do
        kinds = scene.children.map(&:kind)

        expect(scene).to be_a(Sirena::Layout::Requirement::Scene)
        expect(kinds.count("requirement")).to eq(1)
        expect(kinds.count("element")).to eq(1)
      end

      it "transforms the relationship to one edge" do
        expect(scene.edges.length).to eq(1)
      end

      it "renders a non-empty SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
        expect(svg.children).not_to be_empty
      end
    end

    context "with multiple requirement types" do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              functionalRequirement func_req {
              id: F1
              text: System must handle user login
              risk: medium
              verifymethod: test
              }

              performanceRequirement perf_req {
              id: P1
              text: Response time under 2 seconds
              risk: high
              verifymethod: demonstration
              }
        MERMAID
      end

      it "parses both requirements" do
        expect(diagram.requirements.length).to eq(2)
      end

      it "parses the functional requirement's type" do
        func_req = diagram.requirements.find { |r| r.name == "func_req" }

        expect(func_req.type).to eq("functionalRequirement")
      end

      it "parses the performance requirement's type" do
        perf_req = diagram.requirements.find { |r| r.name == "perf_req" }

        expect(perf_req.type).to eq("performanceRequirement")
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with all relationship types" do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              requirement req1 {
              id: 1
              text: Base requirement
              }

              requirement req2 {
              id: 2
              text: Derived requirement
              }

              element elem1 {
              type: component
              }

              req1 - contains -> req2
              req2 - satisfies -> elem1
        MERMAID
      end

      it "parses both relationships" do
        expect(diagram.relationships.length).to eq(2)
      end

      it "parses the contains relationship" do
        rel = diagram.relationships.find { |r| r.type == "contains" }

        expect(rel).not_to be_nil
        expect([rel.source, rel.target]).to eq(%w[req1 req2])
      end

      it "parses the satisfies relationship" do
        rel = diagram.relationships.find { |r| r.type == "satisfies" }

        expect(rel).not_to be_nil
        expect([rel.source, rel.target]).to eq(%w[req2 elem1])
      end
    end

    context "with a styling directive" do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              requirement test_req {
              id: 1
              text: Test requirement
              }

              style test_req fill:#f9f,stroke:#333,stroke-width:4px
        MERMAID
      end

      it "parses one style" do
        expect(diagram.styles.length).to eq(1)
      end

      it "parses the style's target and properties" do
        style = diagram.styles.first

        expect(style.target_ids).to include("test_req")
        expect([style.fill, style.stroke, style.stroke_width])
          .to eq(["#f9f", "#333", "4px"])
      end
    end

    context "with class definitions and assignments" do
      let(:source) do
        <<~MERMAID
          requirementDiagram

              requirement req1 {
              id: 1
              text: Test
              }

              classDef critical fill:#ff0000

              class req1 critical
        MERMAID
      end

      it "parses one class and one assignment" do
        expect(diagram.classes.length).to eq(1)
        expect(diagram.class_assignments.length).to eq(1)
      end

      it "parses the class definition" do
        klass = diagram.classes.first

        expect([klass.name, klass.fill]).to eq(%w[critical #ff0000])
      end

      it "parses the class assignment" do
        assignment = diagram.class_assignments.first

        expect(assignment.target_ids).to include("req1")
        expect(assignment.class_names).to include("critical")
      end
    end
  end

  describe "DiagramRegistry integration" do
    it "has requirement registered" do
      expect(Sirena::DiagramRegistry.registered?(:requirement)).to be true
    end

    it "retrieves requirement handlers" do
      handlers = Sirena::DiagramRegistry.get(:requirement)

      expect(handlers).not_to be_nil
      expect(handlers[:parser]).to eq(Sirena::Parser::Requirement)
      expect(handlers[:transform]).to eq(Sirena::Layout::Requirement)
      expect(handlers[:renderer]).to eq(Sirena::Renderer::Requirement)
    end
  end
end
