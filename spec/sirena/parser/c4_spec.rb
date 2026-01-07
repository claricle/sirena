# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/c4"

RSpec.describe Sirena::Parser::C4Parser do
  let(:parser) { described_class.new }

  describe "#parse" do
    it "parses a minimal C4 diagram" do
      source = "C4 diagram"

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::C4)
      expect(diagram.level).to eq("Context")
    end

    it "parses C4Context header" do
      source = <<~C4
        C4Context
        title System Context diagram
      C4

      diagram = parser.parse(source)

      expect(diagram.level).to eq("Context")
      expect(diagram.title).to eq("System Context diagram")
    end

    it "parses C4Container header" do
      source = <<~C4
        C4Container
        title Container diagram
      C4

      diagram = parser.parse(source)

      expect(diagram.level).to eq("Container")
    end

    it "parses C4Component header" do
      source = <<~C4
        C4Component
        title Component diagram
      C4

      diagram = parser.parse(source)

      expect(diagram.level).to eq("Component")
    end

    it "parses Person element" do
      source = <<~C4
        C4Context
        Person(customer, "Customer", "A customer of the bank")
      C4

      diagram = parser.parse(source)

      expect(diagram.elements.length).to eq(1)
      expect(diagram.elements[0].id).to eq("customer")
      expect(diagram.elements[0].label).to eq("Customer")
      expect(diagram.elements[0].description).to eq("A customer of the bank")
      expect(diagram.elements[0].element_type).to eq("Person")
      expect(diagram.elements[0].person?).to be true
    end

    it "parses Person_Ext element" do
      source = <<~C4
        C4Context
        Person_Ext(external, "External User", "An external user")
      C4

      diagram = parser.parse(source)

      expect(diagram.elements.length).to eq(1)
      expect(diagram.elements[0].element_type).to eq("Person_Ext")
      expect(diagram.elements[0].external).to be true
    end

    it "parses System element" do
      source = <<~C4
        C4Context
        System(banking, "Banking System", "Main banking application")
      C4

      diagram = parser.parse(source)

      expect(diagram.elements.length).to eq(1)
      expect(diagram.elements[0].id).to eq("banking")
      expect(diagram.elements[0].element_type).to eq("System")
      expect(diagram.elements[0].system?).to be true
    end

    it "parses Container element with technology" do
      source = <<~C4
        C4Container
        Container(webapp, "Web App", "Main interface", "React")
      C4

      diagram = parser.parse(source)

      expect(diagram.elements.length).to eq(1)
      expect(diagram.elements[0].id).to eq("webapp")
      expect(diagram.elements[0].technology).to eq("React")
      expect(diagram.elements[0].container?).to be true
    end

    it "parses Component element" do
      source = <<~C4
        C4Component
        Component(controller, "API Controller", "Handles requests", "Spring")
      C4

      diagram = parser.parse(source)

      expect(diagram.elements.length).to eq(1)
      expect(diagram.elements[0].element_type).to eq("Component")
      expect(diagram.elements[0].component?).to be true
    end

    it "parses Rel relationship" do
      source = <<~C4
        C4Context
        Person(customer, "Customer")
        System(banking, "Banking System")
        Rel(customer, banking, "Uses")
      C4

      diagram = parser.parse(source)

      expect(diagram.relationships.length).to eq(1)
      expect(diagram.relationships[0].from_id).to eq("customer")
      expect(diagram.relationships[0].to_id).to eq("banking")
      expect(diagram.relationships[0].label).to eq("Uses")
      expect(diagram.relationships[0].rel_type).to eq("Rel")
    end

    it "parses BiRel relationship" do
      source = <<~C4
        C4Context
        System(systemA, "System A")
        System(systemB, "System B")
        BiRel(systemA, systemB, "Syncs with", "HTTPS")
      C4

      diagram = parser.parse(source)

      expect(diagram.relationships.length).to eq(1)
      expect(diagram.relationships[0].rel_type).to eq("BiRel")
      expect(diagram.relationships[0].technology).to eq("HTTPS")
      expect(diagram.relationships[0].bidirectional?).to be true
    end

    it "parses Enterprise_Boundary" do
      source = <<~C4
        C4Context
        Enterprise_Boundary(b1, "Company Boundary") {
          System(system1, "Internal System")
        }
      C4

      diagram = parser.parse(source)

      expect(diagram.boundaries.length).to eq(1)
      expect(diagram.boundaries[0].id).to eq("b1")
      expect(diagram.boundaries[0].label).to eq("Company Boundary")
      expect(diagram.boundaries[0].boundary_type).to eq("Enterprise_Boundary")
      expect(diagram.boundaries[0].enterprise?).to be true
      expect(diagram.elements.length).to eq(1)
      expect(diagram.elements[0].boundary_id).to eq("b1")
    end

    it "parses System_Boundary" do
      source = <<~C4
        C4Context
        System_Boundary(b1, "System Boundary") {
          Container(c1, "Container 1")
        }
      C4

      diagram = parser.parse(source)

      expect(diagram.boundaries.length).to eq(1)
      expect(diagram.boundaries[0].system?).to be true
    end

    it "parses nested boundaries" do
      source = <<~C4
        C4Context
        Enterprise_Boundary(b1, "Outer") {
          System_Boundary(b2, "Inner") {
            System(sys, "System")
          }
        }
      C4

      diagram = parser.parse(source)

      expect(diagram.boundaries.length).to eq(2)
      # Find the inner boundary
      inner = diagram.boundaries.find { |b| b.id == "b2" }
      expect(inner.parent_id).to eq("b1")
    end

    it "parses elements with attributes" do
      source = <<~C4
        C4Context
        Person(user, "User", "Description", $sprite="person", $link="http://example.com", $tags="tag1,tag2")
      C4

      diagram = parser.parse(source)

      expect(diagram.elements[0].sprite).to eq("person")
      expect(diagram.elements[0].link).to eq("http://example.com")
      expect(diagram.elements[0].tags).to eq("tag1,tag2")
    end

    it "parses UpdateLayoutConfig" do
      source = <<~C4
        C4Context
        UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
      C4

      diagram = parser.parse(source)

      expect(diagram.layout_config).to include("c4ShapeInRow")
      expect(diagram.layout_config).to include("3")
    end

    it "parses complex diagram from fixture" do
      source = File.read("spec/mermaid/c4/007_example_c4_6.mmd")

      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::C4)
      expect(diagram.level).to eq("Context")
      expect(diagram.title).to eq("System Context diagram for Internet Banking System")
      expect(diagram.elements.length).to be > 0
      expect(diagram.relationships.length).to be > 0
      expect(diagram.boundaries.length).to be > 0
    end

    it "validates diagram" do
      source = <<~C4
        C4Context
        Person(customer, "Customer")
        System(banking, "Banking System")
        Rel(customer, banking, "Uses")
      C4

      diagram = parser.parse(source)

      expect(diagram.valid?).to be true
    end

    it "finds elements by id" do
      source = <<~C4
        C4Context
        Person(customer, "Customer")
        System(banking, "Banking System")
      C4

      diagram = parser.parse(source)

      customer = diagram.find_element("customer")
      expect(customer).not_to be_nil
      expect(customer.label).to eq("Customer")
    end

    it "finds relationships from element" do
      source = <<~C4
        C4Context
        Person(customer, "Customer")
        System(banking, "Banking System")
        System(email, "Email System")
        Rel(customer, banking, "Uses")
        Rel(banking, email, "Sends emails")
      C4

      diagram = parser.parse(source)

      rels = diagram.relationships_from("banking")
      expect(rels.length).to eq(1)
      expect(rels[0].to_id).to eq("email")
    end

    it "raises error on invalid syntax" do
      source = "invalid c4 syntax"

      expect { parser.parse(source) }.to raise_error(Sirena::Parser::ParseError)
    end
  end
end