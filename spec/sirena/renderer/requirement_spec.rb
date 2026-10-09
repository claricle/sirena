# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Requirement do
  let(:renderer) { described_class.new }

  describe "#render" do
    context "with basic requirement diagram layout" do
      let(:layout) do
        {
          requirements: {
            "test_req" => {
              requirement: double(
                name: "test_req",
                type: "requirement",
                id: "1",
                text: "the test text.",
                risk: "high",
                verifymethod: "test",
                classes: [],
              ),
              x: 100,
              y: 100,
              width: 180,
              height: 140,
              level: 1,
            },
          },
          elements: {
            "test_entity" => {
              element: double(
                name: "test_entity",
                type: "simulation",
                docref: nil,
                classes: [],
              ),
              x: 100,
              y: 300,
              width: 150,
              height: 80,
              level: 0,
            },
          },
          relationships: [
            {
              relationship: double(source: "test_entity", target: "test_req", type: "satisfies"),
              source: "test_entity",
              target: "test_req",
              type: "satisfies",
              from_x: 175,
              from_y: 380,
              to_x: 190,
              to_y: 240,
            },
          ],
          width: 500,
          height: 500,
        }
      end

      it "renders an SVG document" do
        result = renderer.render(layout)

        expect(result).to be_a(Sirena::Svg::Document)
        expect(result.width).to eq(500)
        expect(result.height).to eq(500)
      end

      it "renders requirements" do
        result = renderer.render(layout)

        # Check that requirement group is created
        requirement_groups = result.children.select do |child|
          child.is_a?(Sirena::Svg::Group) && child.id&.start_with?("requirement-")
        end

        expect(requirement_groups).not_to be_empty
      end

      it "renders elements" do
        result = renderer.render(layout)

        # Check that element group is created
        element_groups = result.children.select do |child|
          child.is_a?(Sirena::Svg::Group) && child.id&.start_with?("element-")
        end

        expect(element_groups).not_to be_empty
      end

      it "renders relationships" do
        result = renderer.render(layout)

        # Check that relationship group is created
        relationship_groups = result.children.select do |child|
          child.is_a?(Sirena::Svg::Group) && child.id&.start_with?("relationship-")
        end

        expect(relationship_groups).not_to be_empty
      end
    end

    context "with empty layout" do
      let(:layout) do
        {
          requirements: {},
          elements: {},
          relationships: [],
          width: 400,
          height: 300,
        }
      end

      it "renders an empty SVG document" do
        result = renderer.render(layout)

        expect(result).to be_a(Sirena::Svg::Document)
        expect(result.width).to eq(400)
        expect(result.height).to eq(300)
      end
    end

    context "with multiple requirements" do
      let(:layout) do
        {
          requirements: {
            "req1" => {
              requirement: double(
                name: "req1",
                type: "functionalRequirement",
                id: "1",
                text: "First requirement",
                risk: "low",
                verifymethod: "test",
                classes: [],
              ),
              x: 50,
              y: 50,
              width: 180,
              height: 140,
              level: 0,
            },
            "req2" => {
              requirement: double(
                name: "req2",
                type: "performanceRequirement",
                id: "2",
                text: "Second requirement",
                risk: "medium",
                verifymethod: "analysis",
                classes: [],
              ),
              x: 250,
              y: 50,
              width: 180,
              height: 140,
              level: 0,
            },
          },
          elements: {},
          relationships: [],
          width: 500,
          height: 300,
        }
      end

      it "renders multiple requirements" do
        result = renderer.render(layout)

        requirement_groups = result.children.select do |child|
          child.is_a?(Sirena::Svg::Group) && child.id&.start_with?("requirement-")
        end

        expect(requirement_groups.size).to eq(2)
      end
    end
  end

  describe "label text" do
    let(:requirement) do
      double(name: "r", type: "requirement", id: "1", text: "the test text.",
             risk: "high", verifymethod: "test", classes: [])
    end
    let(:element) do
      double(name: "e", type: "simulation", docref: "test_ref", classes: [])
    end
    let(:layout) do
      box = { x: 100, y: 100, width: 180, height: 140, level: 1 }
      {
        requirements: { "r" => { requirement: requirement, **box } },
        elements: { "e" => { element: element, **box } },
        relationships: [
          { source: "e", target: "r", type: "satisfies",
            from_x: 175, from_y: 380, to_x: 190, to_y: 240 },
        ],
        width: 500,
        height: 500,
      }
    end
    let(:texts) do
      renderer.render(layout).to_xml.scan(%r{>([^<>]+)</text>}).flatten
    end

    it "draws the text as mermaid does" do
      expect(texts).to include(
        "&lt;&lt;satisfies&gt;&gt;", "&lt;&lt;Requirement&gt;&gt;",
        "&lt;&lt;Element&gt;&gt;", "Text: the test text.", "Verification: Test"
      )
    end

    it "draws the element Doc Ref line after the Type line" do
      pair = ["Type: simulation", "Doc Ref: test_ref"]
      expect(texts.each_cons(2)).to include(pair)
    end

    it "omits the Doc Ref line when the element has none" do
      allow(element).to receive(:docref).and_return(nil)
      expect(texts.grep(/Doc Ref/)).to be_empty
    end

    {
      "requirement" => "Requirement",
      "functionalRequirement" => "Functional Requirement",
      "interfaceRequirement" => "Interface Requirement",
      "performanceRequirement" => "Performance Requirement",
      "physicalRequirement" => "Physical Requirement",
      "designConstraint" => "Design Constraint",
    }.each do |type, label|
      it "labels a #{type} header <<#{label}>> as mermaid does" do
        allow(requirement).to receive(:type).and_return(type)
        expect(texts).to include("&lt;&lt;#{label}&gt;&gt;")
      end
    end
  end

  describe "risk level colors" do
    it "uses correct colors for risk levels" do
      expect(described_class::RISK_COLORS["high"]).to eq("#ff6b6b")
      expect(described_class::RISK_COLORS["medium"]).to eq("#ffd93d")
      expect(described_class::RISK_COLORS["low"]).to eq("#6bcf7f")
    end
  end

  describe "requirement type labels" do
    it "provides labels for all requirement types" do
      expect(described_class::REQUIREMENT_TYPE_LABELS["requirement"]).to eq("Requirement")
      expect(described_class::REQUIREMENT_TYPE_LABELS["functionalRequirement"]).to eq("Functional Requirement")
      expect(described_class::REQUIREMENT_TYPE_LABELS["performanceRequirement"]).to eq("Performance Requirement")
    end
  end
end
