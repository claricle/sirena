# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/c4"
require "sirena/diagram/c4"

RSpec.describe Sirena::Renderer::C4Renderer do
  let(:renderer) { described_class.new }

  describe "#render" do
    it "renders a simple C4 diagram" do
      graph = {
        id: "c4",
        children: [
          {
            id: "customer",
            x: 50,
            y: 50,
            width: 140,
            height: 180,
            labels: [{ text: "Customer", width: 60, height: 14 }],
            metadata: {
              element_type: "Person",
              base_type: "Person",
              external: false,
              person: true,
              system: false,
              container: false,
              component: false
            }
          }
        ],
        edges: [],
        metadata: {
          level: "Context",
          title: "System Context",
          element_count: 1,
          relationship_count: 0
        }
      }

      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.to_xml).to include("customer")
      expect(svg.to_xml).to include("Customer")
    end

    it "renders Person elements with correct styling" do
      graph = {
        id: "c4",
        children: [
          {
            id: "user",
            x: 100,
            y: 100,
            width: 140,
            height: 180,
            labels: [
              { text: "User", width: 30, height: 14 },
              { text: "A system user", width: 80, height: 12 }
            ],
            metadata: {
              element_type: "Person",
              base_type: "Person",
              external: false,
              person: true,
              system: false,
              container: false,
              component: false
            }
          }
        ],
        edges: [],
        metadata: { level: "Context" }
      }

      svg = renderer.render(graph)
      xml = svg.to_xml

      expect(xml).to include("User")
      expect(xml).to include("A system user")
      # Should use Person colors
      expect(xml).to include("#08427B") # Person background
    end

    it "renders external elements with different colors" do
      graph = {
        id: "c4",
        children: [
          {
            id: "ext",
            x: 100,
            y: 100,
            width: 140,
            height: 180,
            labels: [{ text: "External User", width: 80, height: 14 }],
            metadata: {
              element_type: "Person_Ext",
              base_type: "Person",
              external: true,
              person: true,
              system: false,
              container: false,
              component: false
            }
          }
        ],
        edges: [],
        metadata: { level: "Context" }
      }

      svg = renderer.render(graph)
      xml = svg.to_xml

      # Should use external Person colors
      expect(xml).to include("#6C6477") # Person_Ext background
    end

    it "renders System elements" do
      graph = {
        id: "c4",
        children: [
          {
            id: "system",
            x: 100,
            y: 100,
            width: 160,
            height: 120,
            labels: [
              { text: "Banking System", width: 100, height: 14 },
              { text: "Main banking app", width: 100, height: 12 }
            ],
            metadata: {
              element_type: "System",
              base_type: "System",
              external: false,
              person: false,
              system: true,
              container: false,
              component: false
            }
          }
        ],
        edges: [],
        metadata: { level: "Context" }
      }

      svg = renderer.render(graph)
      xml = svg.to_xml

      expect(xml).to include("Banking System")
      expect(xml).to include("#1168BD") # System background
    end

    it "renders relationships with arrows" do
      graph = {
        id: "c4",
        children: [
          {
            id: "user",
            x: 50,
            y: 50,
            width: 140,
            height: 180,
            labels: [{ text: "User", width: 30, height: 14 }],
            metadata: { element_type: "Person", person: true }
          },
          {
            id: "system",
            x: 300,
            y: 50,
            width: 160,
            height: 120,
            labels: [{ text: "System", width: 50, height: 14 }],
            metadata: { element_type: "System", system: true }
          }
        ],
        edges: [
          {
            id: "rel_0",
            sources: ["user"],
            targets: ["system"],
            labels: [{ text: "Uses", width: 30, height: 12 }],
            metadata: { rel_type: "Rel", bidirectional: false }
          }
        ],
        metadata: { level: "Context" }
      }

      svg = renderer.render(graph)
      xml = svg.to_xml

      expect(xml).to include("Uses")
      expect(xml).to include("polygon") # Arrow head
    end

    it "renders bidirectional relationships" do
      graph = {
        id: "c4",
        children: [
          {
            id: "sys1",
            x: 50,
            y: 50,
            width: 160,
            height: 120,
            labels: [{ text: "System 1", width: 60, height: 14 }],
            metadata: { element_type: "System", system: true }
          },
          {
            id: "sys2",
            x: 300,
            y: 50,
            width: 160,
            height: 120,
            labels: [{ text: "System 2", width: 60, height: 14 }],
            metadata: { element_type: "System", system: true }
          }
        ],
        edges: [
          {
            id: "rel_0",
            sources: ["sys1"],
            targets: ["sys2"],
            labels: [
              { text: "Syncs", width: 40, height: 12 },
              { text: "[HTTPS]", width: 50, height: 10 }
            ],
            metadata: { rel_type: "BiRel", bidirectional: true }
          }
        ],
        metadata: { level: "Context" }
      }

      svg = renderer.render(graph)
      xml = svg.to_xml

      expect(xml).to include("Syncs")
      expect(xml).to include("[HTTPS]")
    end

    it "renders boundaries" do
      graph = {
        id: "c4",
        children: [
          {
            id: "boundary1",
            x: 40,
            y: 40,
            width: 400,
            height: 300,
            labels: [{ text: "Enterprise Boundary", width: 120, height: 16 }],
            metadata: {
              boundary_type: "Enterprise_Boundary",
              type_param: nil,
              link: nil,
              tags: nil
            },
            children: [
              {
                id: "system",
                x: 80,
                y: 100,
                width: 160,
                height: 120,
                labels: [{ text: "Internal System", width: 100, height: 14 }],
                metadata: { element_type: "System", system: true }
              }
            ]
          }
        ],
        edges: [],
        metadata: { level: "Context" }
      }

      svg = renderer.render(graph)
      xml = svg.to_xml

      expect(xml).to include("boundary-boundary1")
      expect(xml).to include("Enterprise Boundary")
      expect(xml).to include("stroke-dasharray") # Dashed border
      expect(xml).to include("Internal System")
    end

    it "calculates document dimensions" do
      graph = {
        id: "c4",
        children: [
          {
            id: "elem1",
            x: 50,
            y: 50,
            width: 200,
            height: 150,
            labels: [],
            metadata: { element_type: "System", system: true }
          }
        ],
        edges: [],
        metadata: { level: "Context" }
      }

      svg = renderer.render(graph)

      # Width should be calculated from rightmost element + padding
      # Height should be calculated from bottommost element + padding
      expect(svg.width).to be > 250 # 50 + 200 + padding
      expect(svg.height).to be > 200 # 50 + 150 + padding
    end
  end
end