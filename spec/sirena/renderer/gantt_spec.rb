# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "sirena/renderer/gantt"
require "sirena/layout/gantt"
require "sirena/parser/gantt"

module GanttRendererSpecHelpers
  SIMPLE_SOURCE = <<~GANTT
    gantt
      title Project Timeline
      dateFormat YYYY-MM-DD
      section Planning
      Task 1 :a1, 2024-01-01, 30d
  GANTT
  SECTIONS_SOURCE = <<~GANTT
    gantt
      section Planning
      Task 1 :2024-01-01, 10d
      section Development
      Task 2 :2024-01-11, 15d
  GANTT
  COLORS_SOURCE = <<~GANTT
    gantt
      section Tasks
      Done task :done, 2024-01-01, 5d
      Active task :active, 2024-01-06, 3d
      Critical task :crit, 2024-01-09, 2d
  GANTT
  TAGGED_SOURCE = <<~GANTT
    gantt
      section A section
      Completed task            :done,    des1, 2014-01-06,2014-01-08
  GANTT
  FAR_FUTURE_SOURCE = <<~GANTT
    gantt
      dateFormat YYYY-MM-DD
      section Section
      A task : a1, 2022-10-20, 12d
      Far task : f1, 9999-10-01, 30d
  GANTT
  AXIS_SOURCE = <<~GANTT
    gantt
      dateFormat YYYY-MM-DD
      axisFormat %m-%d
      section Tasks
      Task 1 :2024-01-01, 10d
  GANTT
  COMPACT_SOURCE = <<~GANTT
    gantt
      dateFormat YYYYMMDD
      section Tasks
      T : t, 20240101, 20240103
      U : u, after t, 20240105
  GANTT
  DEPENDENCIES_SOURCE = <<~GANTT
    gantt
      dateFormat YYYY-MM-DD
      section Tasks
      A : a, 2024-01-01, 2024-01-03
      C : c, 2024-01-01, 2024-01-05
      T : t, after a c, 2d
  GANTT
  CHAINED_SOURCE = <<~GANTT
    gantt
      dateFormat YYYY-MM-DD
      section Tasks
      A : a, 2024-01-01, 2d
      T : crit, active, 3d
  GANTT

  def rendered_svg(renderer, source)
    diagram = Sirena::Parser::Gantt.new.parse(source)
    graph = Sirena::Layout::Gantt.new.to_graph(diagram)
    renderer.render(graph)
  end

  def gantt_source(name)
    GanttRendererSpecHelpers.const_get("#{name.to_s.upcase}_SOURCE")
  end

  def rendered_xml(renderer, source)
    rendered_svg(renderer, source).to_xml
  end

  def task_bars(xml, color)
    escaped_color = Regexp.escape(color)
    xml.scan(/<rect fill="#{escaped_color}"[^>]*\/>/)
  end

  def bar_geometry(bar)
    bar.match(/x="([0-9.]+)"[^>]*width="([0-9.]+)"/)
      .captures.map(&:to_f)
  end

  def default_bar_geometries(xml)
    color = Sirena::Renderer::Gantt::TASK_COLORS[:default]
    task_bars(xml, color).map { |bar| bar_geometry(bar) }
  end

  def named_bar_geometries(renderer, source_name)
    xml = rendered_xml(renderer, gantt_source(source_name))
    default_bar_geometries(xml)
  end

  def task_geometry(xml, status)
    color = Sirena::Renderer::Gantt::TASK_COLORS.fetch(status)
    bar_geometry(task_bars(xml, color).first)
  end

  def axis_counts(xml)
    renderer_class = Sirena::Renderer::Gantt
    label_y = renderer_class::MARGIN_TOP + renderer_class::TIMELINE_HEIGHT - 10
    [xml.scan('stroke-dasharray="2,2"').length,
     xml.scan(/<text[^>]*\sy="#{label_y}[^0-9]/).length]
  end
end

RSpec.describe Sirena::Renderer::Gantt do
  include GanttRendererSpecHelpers

  let(:renderer) { described_class.new }

  let(:typed_diagram) do
    Sirena::Parser::Gantt.new.parse(<<~GANTT)
      gantt
        section Planning
        Task 1 :a1, 2024-01-01, 30d
    GANTT
  end

  let(:typed_scene_state) do
    scene = Sirena::Layout::Gantt.new.call(typed_diagram)
    [scene.class, scene.sections.first.tasks.first.start_date,
     typed_diagram.sections.first.tasks.first.calculated_start]
  end

  describe "#render" do
    it "returns a typed Scene without mutating diagram dates" do
      expected = [Sirena::Layout::Gantt::Scene, Date.new(2024, 1, 1), nil]
      expect(typed_scene_state).to eq(expected)
    end

    it "renders a simple Gantt chart to SVG" do
      svg = rendered_svg(renderer, gantt_source(:simple))
      expect([svg.class, svg.to_xml.include?("Project Timeline"),
              svg.to_xml.include?("<svg")])
        .to eq([Sirena::Svg::Document, true, true])
    end

    it "renders multiple sections" do
      xml = rendered_xml(renderer, gantt_source(:sections))
      expect([xml.include?("Planning"), xml.include?("Development")])
        .to eq([true, true])
    end

    it "renders task bars with proper colors" do
      xml = rendered_xml(renderer, gantt_source(:colors))
      expect([xml.include?("<rect"), xml.include?("fill")])
        .to eq([true, true])
    end

    it "renders a task tagged with an id and explicit start/end dates " \
       "(corpus gantt/005)" do
      xml = rendered_xml(renderer, gantt_source(:tagged))
      # The timeline and section backgrounds are also <rect> elements, so a
      # bare `include("<rect")` passes even with the task bar itself never
      # drawn. Pin the bar's own color and its rounded-corner geometry,
      # which only render_task_bar produces.
      done_color = described_class::TASK_COLORS[:done]
      bar = /<rect fill="#{Regexp.escape(done_color)}"[^>]*\brx="/
      expect([xml.include?("Completed task"), xml.match?(bar)])
        .to eq([true, true])
    end

    # mermaid accepts any year, so an explicit far-future date is valid
    # input (corpus gantt/001). calculate_label_interval used to cap at a
    # flat 30-day step regardless of range, which for a multi-millennium
    # span builds tens of thousands of label/grid-line nodes and blows
    # well past the corpus sweep's 10s timeout.
    it "bounds the number of axis labels for a multi-millennium timeline" do
      xml = nil
      source = gantt_source(:far_future)
      Timeout.timeout(5) { xml = rendered_xml(renderer, source) }

      # Both bounds matter: the upper one is the timeout fix under test, the
      # lower one catches an axis that silently stopped rendering entirely.
      expect(axis_counts(xml)).to all(be_between(1, 41))
    end

    it "renders timeline axis" do
      expect(rendered_xml(renderer, gantt_source(:axis))).to include("<text")
    end

    # `dateFormat YYYYMMDD` has no separator, so its date fields ("20240101")
    # used to fall through the id-by-shape branch and overwrite the id the
    # three-slot positional rule had already assigned — the task then had no
    # id, `resolve_task_dependency` could never find it, and both bars
    # rendered as 20px stubs (Codex round 3 High, gantt.rb:202). Fixed, the
    # bars carry their real 2-day widths and sit flush against each other,
    # exactly as mmdc renders this input (widths 317/317, U.x = T.x + T.width).
    it "renders real task widths, not 20px stubs, when dateFormat " \
       "is compact digits" do
      bars = named_bar_geometries(renderer, :compact)
      t_x, t_width = bars[0]
      u_x = bars[1][0]

      expect([t_width, u_x])
        .to match([be > 20, be_within(0.01).of(t_x + t_width)])
    end

    # "after a c" names two dependencies; mermaid starts the task once BOTH
    # are done, i.e. after the LATEST of their ends. The resolver used to
    # look up the literal string "a c" as one task id, find nothing, and
    # leave the task's dates nil forever (Codex round 3 High, gantt.rb:186).
    # mmdc places T flush against C's end (C ends later than A) at the same
    # relative geometry asserted here.
    it "starts a task after the latest of several space-separated " \
       "dependencies" do
      bars = named_bar_geometries(renderer, :dependencies)
      c_x, c_width = bars[1]
      t_x = bars[2][0]

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
      xml = rendered_xml(renderer, gantt_source(:chained))
      a_x, a_width = task_geometry(xml, :default)
      t_x, t_width = task_geometry(xml, :critical)

      expect([t_width, t_x])
        .to match([be > 20, be_within(0.01).of(a_x + a_width)])
    end
  end
end
