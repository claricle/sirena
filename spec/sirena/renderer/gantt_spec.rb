# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/gantt"
require "sirena/transform/gantt"
require "sirena/parser/gantt"

RSpec.describe Sirena::Renderer::GanttRenderer do
  let(:renderer) { described_class.new }

  describe "#render" do
    it "renders a simple Gantt chart to SVG" do
      source = <<~GANTT
        gantt
          title Project Timeline
          dateFormat YYYY-MM-DD
          section Planning
          Task 1 :a1, 2024-01-01, 30d
      GANTT

      parser = Sirena::Parser::GanttParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::GanttTransform.new
      graph = transform.to_graph(diagram)

      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.to_xml).to include("Project Timeline")
      expect(svg.to_xml).to include("<svg")
    end

    it "renders multiple sections" do
      source = <<~GANTT
        gantt
          section Planning
          Task 1 :2024-01-01, 10d
          section Development
          Task 2 :2024-01-11, 15d
      GANTT

      parser = Sirena::Parser::GanttParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::GanttTransform.new
      graph = transform.to_graph(diagram)

      svg = renderer.render(graph)
      xml = svg.to_xml

      expect(xml).to include("Planning")
      expect(xml).to include("Development")
    end

    it "renders task bars with proper colors" do
      source = <<~GANTT
        gantt
          section Tasks
          Done task :done, 2024-01-01, 5d
          Active task :active, 2024-01-06, 3d
          Critical task :crit, 2024-01-09, 2d
      GANTT

      parser = Sirena::Parser::GanttParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::GanttTransform.new
      graph = transform.to_graph(diagram)

      svg = renderer.render(graph)
      xml = svg.to_xml

      # Should contain colored rectangles for tasks
      expect(xml).to include("<rect")
      expect(xml).to include("fill")
    end

    it "renders timeline axis" do
      source = <<~GANTT
        gantt
          dateFormat YYYY-MM-DD
          axisFormat %m-%d
          section Tasks
          Task 1 :2024-01-01, 10d
      GANTT

      parser = Sirena::Parser::GanttParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::GanttTransform.new
      graph = transform.to_graph(diagram)

      svg = renderer.render(graph)
      xml = svg.to_xml

      # Should include timeline with date labels
      expect(xml).to include("<text")
    end
  end
end