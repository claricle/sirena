# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/architecture"
require "sirena/diagram/architecture"

RSpec.describe Sirena::Renderer::ArchitectureRenderer do
  let(:renderer) { described_class.new }

  describe "#render" do
    let(:diagram) do
      Sirena::Diagram::ArchitectureDiagram.new(
        services: [
          Sirena::Diagram::ArchitectureDiagram::Service.new(
            id: "db",
            label: "Database",
            icon: "database",
            group_id: nil
          ),
          Sirena::Diagram::ArchitectureDiagram::Service.new(
            id: "server",
            label: "Server",
            icon: "server",
            group_id: nil
          ),
        ],
        groups: [],
        edges: [
          Sirena::Diagram::ArchitectureDiagram::Edge.new(
            from_id: "db",
            to_id: "server",
            from_position: "R",
            to_position: "L",
            label: nil
          ),
        ]
      )
    end

    let(:layout) do
      {
        services: {
          "db" => {
            service: diagram.services[0],
            x: 40,
            y: 40,
            width: 120,
            height: 80,
            group_id: :root,
          },
          "server" => {
            service: diagram.services[1],
            x: 200,
            y: 40,
            width: 120,
            height: 80,
            group_id: :root,
          },
        },
        groups: {},
        edges: [
          {
            edge: diagram.edges[0],
            from_x: 160,
            from_y: 80,
            to_x: 200,
            to_y: 80,
          },
        ],
        width: 400,
        height: 200,
      }
    end

    it "renders an SVG document" do
      svg = renderer.render(layout)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.width).to eq(400)
      expect(svg.height).to eq(200)
    end

    it "renders services" do
      svg = renderer.render(layout)
      svg_string = svg.to_s

      expect(svg_string).to include('id="service-db"')
      expect(svg_string).to include('id="service-server"')
    end

    it "renders service labels" do
      svg = renderer.render(layout)
      svg_string = svg.to_s

      expect(svg_string).to include("Database")
      expect(svg_string).to include("Server")
    end

    it "renders edges" do
      svg = renderer.render(layout)
      svg_string = svg.to_s

      expect(svg_string).to include('id="edge-db-server"')
    end

    context "with groups" do
      let(:diagram_with_groups) do
        Sirena::Diagram::ArchitectureDiagram.new(
          services: [
            Sirena::Diagram::ArchitectureDiagram::Service.new(
              id: "db",
              label: "Database",
              icon: "database",
              group_id: "api"
            ),
          ],
          groups: [
            Sirena::Diagram::ArchitectureDiagram::Group.new(
              id: "api",
              label: "API",
              icon: "cloud",
              parent_id: nil
            ),
          ],
          edges: []
        )
      end

      let(:layout_with_groups) do
        {
          services: {
            "db" => {
              service: diagram_with_groups.services[0],
              x: 70,
              y: 70,
              width: 120,
              height: 80,
              group_id: "api",
            },
          },
          groups: {
            "api" => {
              group: diagram_with_groups.groups[0],
              x: 40,
              y: 40,
              width: 180,
              height: 140,
            },
          },
          edges: [],
          width: 300,
          height: 250,
        }
      end

      it "renders group boundaries" do
        svg = renderer.render(layout_with_groups)
        svg_string = svg.to_s

        expect(svg_string).to include('id="group-api"')
      end

      it "renders group labels" do
        svg = renderer.render(layout_with_groups)
        svg_string = svg.to_s

        expect(svg_string).to include("API")
      end
    end

    context "with edge labels" do
      let(:layout_with_label) do
        layout_copy = layout.dup
        layout_copy[:edges] = [
          {
            edge: Sirena::Diagram::ArchitectureDiagram::Edge.new(
              from_id: "db",
              to_id: "server",
              from_position: "R",
              to_position: "L",
              label: "HTTP"
            ),
            from_x: 160,
            from_y: 80,
            to_x: 200,
            to_y: 80,
          },
        ]
        layout_copy
      end

      it "renders edge labels" do
        svg = renderer.render(layout_with_label)
        svg_string = svg.to_s

        expect(svg_string).to include("HTTP")
      end
    end
  end
end