# frozen_string_literal: true

require "spec_helper"
require "timeout"
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

    it "renders a task tagged with an id and explicit start/end dates (corpus gantt/005)" do
      source = <<~GANTT
        gantt
          section A section
          Completed task            :done,    des1, 2014-01-06,2014-01-08
      GANTT

      parser = Sirena::Parser::GanttParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::GanttTransform.new
      graph = transform.to_graph(diagram)

      svg = renderer.render(graph)
      xml = svg.to_xml

      # The timeline and section backgrounds are also <rect> elements, so a
      # bare `include("<rect")` passes even with the task bar itself never
      # drawn. Pin the bar's own color and its rounded-corner geometry,
      # which only render_task_bar produces.
      done_color = described_class::TASK_COLORS[:done]
      expect(xml).to include("Completed task")
      expect(xml).to match(/<rect fill="#{Regexp.escape(done_color)}"[^>]*\brx="/)
    end

    # mermaid accepts any year, so an explicit far-future date is valid
    # input (corpus gantt/001). calculate_label_interval used to cap at a
    # flat 30-day step regardless of range, which for a multi-millennium
    # span builds tens of thousands of label/grid-line nodes and blows
    # well past the corpus sweep's 10s timeout.
    it "bounds the number of axis labels for a multi-millennium timeline" do
      source = <<~GANTT
        gantt
          dateFormat YYYY-MM-DD
          section Section
          A task : a1, 2022-10-20, 12d
          Far task : f1, 9999-10-01, 30d
      GANTT

      parser = Sirena::Parser::GanttParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::GanttTransform.new
      graph = transform.to_graph(diagram)

      xml = nil
      Timeout.timeout(5) { xml = renderer.render(graph).to_xml }

      grid_line_count = xml.scan('stroke-dasharray="2,2"').length
      label_y = described_class::MARGIN_TOP + described_class::TIMELINE_HEIGHT - 10
      label_count = xml.scan(/<text[^>]*\sy="#{label_y}[^0-9]/).length

      # Both bounds matter: the upper one is the timeout fix under test, the
      # lower one catches an axis that silently stopped rendering entirely.
      expect(grid_line_count).to be_between(1, 41)
      expect(label_count).to be_between(1, 41)
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