# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/gantt"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Gantt do
  let(:diagram_class) do
    Class.new(Sirena::Diagram::Gantt) do
      attr_accessor :acc_title, :acc_description
    end
  end
  let(:diagram) do
    diagram_class.new.tap do |gantt|
      gantt.id = "section_0"
      gantt.title = "Release plan"
      gantt.acc_title = "Accessible release plan"
      gantt.acc_description = "Planning and shipping tasks"
      gantt.date_format = "YYYY-MM-DD"
      gantt.axis_format = "%m/%d"
      gantt.tick_interval = "1week"
      gantt.excludes = %w[weekends 2024-02-01]
      gantt.weekend = "friday"
      gantt.inclusive_end_dates = true
      gantt.today_marker = "off"
      gantt.sections = [planning_section, shipping_section]
    end
  end
  let(:ir) { described_class.call(diagram) }

  it "produces valid collision-free pre-positioned IR" do
    expect(ir).to be_valid
  end

  it "preserves root identity, title, and accessibility" do
    expect([ir.id, ir.label, ir.role, ir.accessibility_title,
            ir.accessibility_description])
      .to eq(["section_0", "Release plan", "schedule",
              "Accessible release plan", "Planning and shipping tasks"])
  end

  it "preserves scheduling settings and ordered exclusions" do
    expect(setting_evidence)
      .to eq([expected_settings, expected_exclusions])
  end

  it "preserves ordered sections, tasks, constraints, flags, and actions" do
    sections = children(nil, "section")
    tasks = sections.flat_map { |section| children(section.id, "task") }

    expect([sections.map(&:label), tasks.map { |task| task_signature(task) }])
      .to eq([%w[Planning Shipping], expected_tasks])
  end

  it "represents resolvable dependencies without canvas geometry" do
    expect(dependency_evidence)
      .to eq([[], [["starts_after", "Design", "Build"],
                   ["ends_at_start", "Build", "Release"]]])
  end

  def planning_section
    Sirena::Diagram::GanttSection.new("Planning").tap do |section|
      section.tasks = [task(description: "Design", id: "section_0",
                            start_date: "2024-01-01", duration: "2d")]
    end
  end

  def shipping_section
    Sirena::Diagram::GanttSection.new("Shipping").tap do |section|
      section.tasks = [
        task(description: "Build", id: "build", after_task: "section_0",
             until_task: "release", tags: %w[crit active],
             click_href: "https://example.test/build"),
        task(description: "Release", id: "release",
             start_date: "2024-01-05", end_date: "2024-01-06",
             tags: %w[milestone done], click_callback: "ship"),
      ]
    end
  end

  def task(**attributes)
    Sirena::Diagram::GanttTask.new.tap do |gantt_task|
      attributes.each do |name, value|
        gantt_task.public_send("#{name}=", value)
      end
    end
  end

  def setting_evidence
    settings = ir.items.find { |item| item.role == "schedule_settings" }
    values = settings.placements.to_h do |placement|
      [placement.dimension, placement.value.value]
    end
    exclusions = children(settings.id, "exclusion").map(&:label)
    [values, exclusions]
  end

  def dependency_evidence
    [placement_dimensions & %w[x y width height],
     ir.connections.map { |edge| edge_signature(edge) }]
  end

  def placement_dimensions
    ir.items.flat_map(&:placements).map(&:dimension)
  end

  def edge_signature(edge)
    [edge.role, item(edge.source_id).label, item(edge.target_id).label]
  end

  def children(parent_id, role)
    ir.items.select do |candidate|
      candidate.parent_id == parent_id && candidate.role == role
    end.sort_by { |candidate| value(candidate, "source_order") }
  end

  def item(id)
    ir.items.find { |candidate| candidate.id == id }
  end

  def task_signature(task_item)
    flags = children(task_item.id, "status_flag").map(&:label)
    [task_item.label, value(task_item, "source_id"),
     value(task_item, "start_date"), value(task_item, "end_date"),
     value(task_item, "duration"), value(task_item, "after_tasks"),
     value(task_item, "until_task"), flags,
     value(task_item, "click_href"), value(task_item, "click_callback")]
  end

  def value(item, dimension)
    item.placements.find { |placement| placement.dimension == dimension }
      &.value&.value
  end

  def expected_settings
    {
      "date_format" => "YYYY-MM-DD", "axis_format" => "%m/%d",
      "tick_interval" => "1week", "weekend" => "friday",
      "inclusive_end_dates" => true, "today_marker" => "off"
    }
  end

  def expected_exclusions
    %w[weekends 2024-02-01]
  end

  def expected_tasks
    [
      ["Design", "section_0", "2024-01-01", nil, "2d", nil, nil, [], nil, nil],
      ["Build", "build", nil, nil, nil, "section_0", "release",
       %w[crit active], "https://example.test/build", nil],
      ["Release", "release", "2024-01-05", "2024-01-06", nil, nil, nil,
       %w[milestone done], nil, "ship"],
    ]
  end
end
