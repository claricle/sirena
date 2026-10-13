# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/c4"

RSpec.describe Sirena::Parser::C4, :aggregate_failures do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "when parsing a minimal C4 diagram" do
      let(:source) { "C4 diagram" }
      let(:diagram) { parser.parse(source) }

      it "retains diagram" do
        expect(diagram).to be_a(Sirena::Diagram::C4)
      end

      it "retains diagram.level" do
        expect(diagram.level).to eq("Context")
      end
    end

    context "when parsing C4Context header" do
      let(:source) do
        <<~C4
          C4Context
          title System Context diagram
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.level" do
        expect(diagram.level).to eq("Context")
      end

      it "retains diagram.title" do
        expect(diagram.title).to eq("System Context diagram")
      end
    end

    context "when parsing C4Container header" do
      let(:source) do
        <<~C4
          C4Container
          title Container diagram
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.level" do
        expect(diagram.level).to eq("Container")
      end
    end

    context "when parsing C4Component header" do
      let(:source) do
        <<~C4
          C4Component
          title Component diagram
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.level" do
        expect(diagram.level).to eq("Component")
      end
    end

    context "when parsing Person element" do
      let(:source) do
        <<~C4
          C4Context
          Person(customer, "Customer", "A customer of the bank")
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.elements.length" do
        expect(diagram.elements.length).to eq(1)
      end

      it "retains diagram.elements 0 .id" do
        expect(diagram.elements[0].id).to eq("customer")
      end

      it "retains diagram.elements 0 .label" do
        expect(diagram.elements[0].label).to eq("Customer")
      end

      it "retains diagram.elements 0 .description" do
        expect(diagram.elements[0].description).to eq("A customer of the bank")
      end

      it "retains diagram.elements 0 .element_type" do
        expect(diagram.elements[0].element_type).to eq("Person")
      end

      it "retains diagram.elements 0 .person" do
        expect(diagram.elements[0].person?).to be true
      end
    end

    context "when parsing Person_Ext element" do
      let(:source) do
        <<~C4
          C4Context
          Person_Ext(external, "External User", "An external user")
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.elements.length" do
        expect(diagram.elements.length).to eq(1)
      end

      it "retains diagram.elements 0 .element_type" do
        expect(diagram.elements[0].element_type).to eq("Person_Ext")
      end

      it "retains diagram.elements 0 .external" do
        expect(diagram.elements[0].external).to be true
      end
    end

    context "when parsing System element" do
      let(:source) do
        <<~C4
          C4Context
          System(banking, "Banking System", "Main banking application")
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.elements.length" do
        expect(diagram.elements.length).to eq(1)
      end

      it "retains diagram.elements 0 .id" do
        expect(diagram.elements[0].id).to eq("banking")
      end

      it "retains diagram.elements 0 .element_type" do
        expect(diagram.elements[0].element_type).to eq("System")
      end

      it "retains diagram.elements 0 .system" do
        expect(diagram.elements[0].system?).to be true
      end
    end

    context "when parsing Container element with technology" do
      let(:source) do
        <<~C4
          C4Container
          Container(webapp, "Web App", "Main interface", "React")
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.elements.length" do
        expect(diagram.elements.length).to eq(1)
      end

      it "retains diagram.elements 0 .id" do
        expect(diagram.elements[0].id).to eq("webapp")
      end

      it "retains diagram.elements 0 .technology" do
        expect(diagram.elements[0].technology).to eq("React")
      end

      it "retains diagram.elements 0 .container" do
        expect(diagram.elements[0].container?).to be true
      end
    end

    context "when parsing Component element" do
      let(:source) do
        <<~C4
          C4Component
          Component(controller, "API Controller", "Handles requests", "Spring")
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.elements.length" do
        expect(diagram.elements.length).to eq(1)
      end

      it "retains diagram.elements 0 .element_type" do
        expect(diagram.elements[0].element_type).to eq("Component")
      end

      it "retains diagram.elements 0 .component" do
        expect(diagram.elements[0].component?).to be true
      end
    end

    context "when parsing Rel relationship" do
      let(:source) do
        <<~C4
          C4Context
          Person(customer, "Customer")
          System(banking, "Banking System")
          Rel(customer, banking, "Uses")
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.relationships.length" do
        expect(diagram.relationships.length).to eq(1)
      end

      it "retains diagram.relationships 0 .from_id" do
        expect(diagram.relationships[0].from_id).to eq("customer")
      end

      it "retains diagram.relationships 0 .to_id" do
        expect(diagram.relationships[0].to_id).to eq("banking")
      end

      it "retains diagram.relationships 0 .label" do
        expect(diagram.relationships[0].label).to eq("Uses")
      end

      it "retains diagram.relationships 0 .rel_type" do
        expect(diagram.relationships[0].rel_type).to eq("Rel")
      end
    end

    context "when parsing BiRel relationship" do
      let(:source) do
        <<~C4
          C4Context
          System(systemA, "System A")
          System(systemB, "System B")
          BiRel(systemA, systemB, "Syncs with", "HTTPS")
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.relationships.length" do
        expect(diagram.relationships.length).to eq(1)
      end

      it "retains diagram.relationships 0 .rel_type" do
        expect(diagram.relationships[0].rel_type).to eq("BiRel")
      end

      it "retains diagram.relationships 0 .technology" do
        expect(diagram.relationships[0].technology).to eq("HTTPS")
      end

      it "retains diagram.relationships 0 .bidirectional" do
        expect(diagram.relationships[0].bidirectional?).to be true
      end
    end

    context "when parsing Enterprise_Boundary" do
      let(:source) do
        <<~C4
          C4Context
          Enterprise_Boundary(b1, "Company Boundary") {
            System(system1, "Internal System")
          }
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.boundaries.length" do
        expect(diagram.boundaries.length).to eq(1)
      end

      it "retains diagram.boundaries 0 .id" do
        expect(diagram.boundaries[0].id).to eq("b1")
      end

      it "retains diagram.boundaries 0 .label" do
        expect(diagram.boundaries[0].label).to eq("Company Boundary")
      end

      it "retains diagram.boundaries 0 .boundary_type" do
        expect(diagram.boundaries[0].boundary_type).to eq("Enterprise_Boundary")
      end

      it "retains diagram.boundaries 0 .enterprise" do
        expect(diagram.boundaries[0].enterprise?).to be true
      end

      it "retains diagram.elements.length" do
        expect(diagram.elements.length).to eq(1)
      end

      it "retains diagram.elements 0 .boundary_id" do
        expect(diagram.elements[0].boundary_id).to eq("b1")
      end
    end

    context "when parsing System_Boundary" do
      let(:source) do
        <<~C4
          C4Context
          System_Boundary(b1, "System Boundary") {
            Container(c1, "Container 1")
          }
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.boundaries.length" do
        expect(diagram.boundaries.length).to eq(1)
      end

      it "retains diagram.boundaries 0 .system" do
        expect(diagram.boundaries[0].system?).to be true
      end
    end

    context "when parsing nested boundaries" do
      let(:source) do
        <<~C4
          C4Context
          Enterprise_Boundary(b1, "Outer") {
            System_Boundary(b2, "Inner") {
              System(sys, "System")
            }
          }
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.boundaries.length" do
        expect(diagram.boundaries.length).to eq(2)
      end

      it "retains inner.parent_id" do
        inner = diagram.boundaries.find { |b| b.id == "b2" }

        expect(inner.parent_id).to eq("b1")
      end
    end

    context "when parsing elements with attributes" do
      let(:source) do
        <<~C4
          C4Context
          Person(user, "User", "Description", $sprite="person", $link="http://example.com", $tags="tag1,tag2")
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.elements 0 .sprite" do
        expect(diagram.elements[0].sprite).to eq("person")
      end

      it "retains diagram.elements 0 .link" do
        expect(diagram.elements[0].link).to eq("http://example.com")
      end

      it "retains diagram.elements 0 .tags" do
        expect(diagram.elements[0].tags).to eq("tag1,tag2")
      end
    end

    context "when parsing UpdateLayoutConfig" do
      let(:source) do
        <<~C4
          C4Context
          UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains the shape layout option" do
        expect(diagram.layout_config).to include("c4ShapeInRow")
      end

      it "retains the shape layout value" do
        expect(diagram.layout_config).to include("3")
      end
    end

    context "when parsing complex diagram from fixture" do
      let(:source) do
        File.read(File.expand_path("../../mermaid/c4/c4-8ab0b1ef.mmd", __dir__))
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram" do
        expect(diagram).to be_a(Sirena::Diagram::C4)
      end

      it "retains diagram.level" do
        expect(diagram.level).to eq("Context")
      end

      it "retains diagram.title" do
        expect(diagram.title).to eq("System Context diagram for Internet Banking System")
      end

      it "retains diagram.elements.length" do
        expect(diagram.elements.length).to be > 0
      end

      it "retains diagram.relationships.length" do
        expect(diagram.relationships.length).to be > 0
      end

      it "retains diagram.boundaries.length" do
        expect(diagram.boundaries.length).to be > 0
      end
    end

    context "when validates diagram" do
      let(:source) do
        <<~C4
          C4Context
          Person(customer, "Customer")
          System(banking, "Banking System")
          Rel(customer, banking, "Uses")
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.valid" do
        expect(diagram.valid?).to be true
      end
    end

    context "when finds elements by id" do
      let(:source) do
        <<~C4
          C4Context
          Person(customer, "Customer")
          System(banking, "Banking System")
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains customer" do
        customer = diagram.find_element("customer")

        expect(customer).not_to be_nil
      end

      it "retains customer.label" do
        customer = diagram.find_element("customer")

        expect(customer.label).to eq("Customer")
      end
    end

    context "when finds relationships from element" do
      let(:source) do
        <<~C4
          C4Context
          Person(customer, "Customer")
          System(banking, "Banking System")
          System(email, "Email System")
          Rel(customer, banking, "Uses")
          Rel(banking, email, "Sends emails")
        C4
      end
      let(:diagram) { parser.parse(source) }

      it "retains rels.length" do
        rels = diagram.relationships_from("banking")

        expect(rels.length).to eq(1)
      end

      it "retains rels 0 .to_id" do
        rels = diagram.relationships_from("banking")

        expect(rels[0].to_id).to eq("email")
      end
    end

    it "parses $link and $tags on nested boundaries" do
      source = "C4Context\nBoundary(o, \"O\") {\nBoundary(m, \"M\") {\n" \
               "Boundary(b, \"B\", $link=\"https://x\", $tags=\"t\") " \
               "{\n}\n}\n}\n"
      inner = parser.parse(source).boundaries.find { |b| b.id == "b" }

      expect([inner.link, inner.tags]).to eq(["https://x", "t"])
    end

    it "raises error on invalid syntax" do
      source = "invalid c4 syntax"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end
  end

  describe "#parse single-parameter layout config and nested boundaries" do
    it "keeps a lone UpdateLayoutConfig parameter" do
      source = "C4Context\nUpdateLayoutConfig($c4ShapeInRow=\"2\")\n"

      expect(parser.parse(source).layout_config).to eq("$c4ShapeInRow=2")
    end

    context "with a boundary inside a boundary" do
      let(:source) do
        <<~C4
          C4Context
          Boundary(b1, "Outer") {
            Person(p, "P")
            Boundary(b2, "Inner") {
              System(s, "S")
            }
          }
        C4
      end
      let(:boundaries) { parser.parse(source).boundaries.to_h { [_1.id, _1] } }

      it "lists the inner boundary under the outer one" do
        expect(boundaries["b1"].boundary_ids).to eq(["b2"])
      end

      it "points the inner boundary at its parent" do
        expect(boundaries["b2"].parent_id).to eq("b1")
      end

      it "keeps the element inside the inner boundary" do
        expect(boundaries["b2"].element_ids).to eq(["s"])
      end
    end
  end
end
