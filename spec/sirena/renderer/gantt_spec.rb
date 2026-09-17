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

    # `dateFormat YYYYMMDD` has no separator, so its date fields ("20240101")
    # used to fall through the id-by-shape branch and overwrite the id the
    # three-slot positional rule had already assigned — the task then had no
    # id, `resolve_task_dependency` could never find it, and both bars
    # rendered as 20px stubs (Codex round 3 High, gantt.rb:202). Fixed, the
    # bars carry their real 2-day widths and sit flush against each other,
    # exactly as mmdc renders this input (widths 317/317, U.x = T.x + T.width).
    it "renders real task widths, not 20px stubs, when dateFormat is compact digits" do
      source = <<~GANTT
        gantt
          dateFormat YYYYMMDD
          section Tasks
          T : t, 20240101, 20240103
          U : u, after t, 20240105
      GANTT

      parser = Sirena::Parser::GanttParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::GanttTransform.new
      graph = transform.to_graph(diagram)

      xml = renderer.render(graph).to_xml
      bars = xml.scan(/<rect fill="#{Regexp.escape(described_class::TASK_COLORS[:default])}"[^>]*\/>/)
      t_x, t_width = bars[0].match(/x="([0-9.]+)"[^>]*width="([0-9.]+)"/).captures.map(&:to_f)
      u_x = bars[1].match(/x="([0-9.]+)"/)[1].to_f

      expect(t_width).to be > 20
      expect(u_x).to be_within(0.01).of(t_x + t_width)
    end

    # "after a c" names two dependencies; mermaid starts the task once BOTH
    # are done, i.e. after the LATEST of their ends. The resolver used to
    # look up the literal string "a c" as one task id, find nothing, and
    # leave the task's dates nil forever (Codex round 3 High, gantt.rb:186).
    # mmdc places T flush against C's end (C ends later than A) at the same
    # relative geometry asserted here.
    it "starts a task after the latest of several space-separated dependencies" do
      source = <<~GANTT
        gantt
          dateFormat YYYY-MM-DD
          section Tasks
          A : a, 2024-01-01, 2024-01-03
          C : c, 2024-01-01, 2024-01-05
          T : t, after a c, 2d
      GANTT

      parser = Sirena::Parser::GanttParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::GanttTransform.new
      graph = transform.to_graph(diagram)

      xml = renderer.render(graph).to_xml
      bars = xml.scan(/<rect fill="#{Regexp.escape(described_class::TASK_COLORS[:default])}"[^>]*\/>/)
      _a_x, _a_width, c_x, c_width, t_x, _t_width =
        bars.flat_map { |bar| bar.match(/x="([0-9.]+)"[^>]*width="([0-9.]+)"/).captures }.map(&:to_f)

      expect(t_x).to be_within(0.01).of(c_x + c_width)
    end

    # A task naming only tags and a duration — no start date, no "after",
    # no "until" — is scheduled immediately after the PREVIOUS task in
    # declaration order (mermaid's implicit chaining). The parser accepts
    # this comma-tag form (it used to raise ParseError before this diff),
    # but nothing scheduled it: it skipped the first pass (no start_date)
    # and the second pass (no after_task/until_task), so its calculated
    # dates stayed nil forever and it rendered as a 20px stub at the origin
    # (Codex High, transform/gantt.rb:65). mmdc starts it flush against the
    # previous task's end.
    it "chains a duration-only tagged task after the previous task" do
      source = <<~GANTT
        gantt
          dateFormat YYYY-MM-DD
          section Tasks
          A : a, 2024-01-01, 2d
          T : crit, active, 3d
      GANTT

      parser = Sirena::Parser::GanttParser.new
      diagram = parser.parse(source)

      transform = Sirena::Transform::GanttTransform.new
      graph = transform.to_graph(diagram)

      xml = renderer.render(graph).to_xml
      a_bar = xml.match(/<rect fill="#{Regexp.escape(described_class::TASK_COLORS[:default])}"[^>]*\/>/)[0]
      a_x, a_width = a_bar.match(/x="([0-9.]+)"[^>]*width="([0-9.]+)"/).captures.map(&:to_f)
      t_bar = xml.match(/<rect fill="#{Regexp.escape(described_class::TASK_COLORS[:critical])}"[^>]*\/>/)[0]
      t_x, t_width = t_bar.match(/x="([0-9.]+)"[^>]*width="([0-9.]+)"/).captures.map(&:to_f)

      expect(t_width).to be > 20
      expect(t_x).to be_within(0.01).of(a_x + a_width)
    end
  end
end