# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Gantt do
  let(:source) do
    <<~MERMAID
      gantt
        title Release plan
        dateFormat YYYY-MM-DD
        axisFormat %m/%d
        excludes weekends
        section Planning
        Design :crit, design, 2024-01-01, 2d
        section Shipping
        Build :active, build, after design, 2d
        Release :milestone, done, release, after build, 0d
    MERMAID
  end
  let(:diagram) do
    Sirena::Parser::Gantt.new.parse(source).tap do |parsed|
      parsed.id = "plan"
    end
  end
  let(:reference_date) { Date.new(2024, 1, 1) }

  it "lays out shared pre-positioned IR identically to the private model" do
    ir = Sirena::Notation::Mermaid::IRAdapters::Gantt.call(diagram)
    private_scene = described_class.new.call(diagram, today: reference_date)
    ir_scene = described_class.new.call(ir, today: reference_date)

    expect(Marshal.dump(ir_scene)).to eq(Marshal.dump(private_scene))
  end

  it "keeps scheduling calculation out of the private model" do
    described_class.new.call(diagram, today: reference_date)

    dates = diagram.sections.flat_map(&:tasks).flat_map do |task|
      [task.calculated_start, task.calculated_end]
    end
    expect(dates).to all(be_nil)
  end

  it "turns ordered constraints into typed final-canvas geometry" do
    expect(geometry_evidence).to eq(expected_geometry)
  end

  it "does not send its hand-laid-out scene through Grid" do
    calls = []
    allow(Sirena::Layout::Grid).to receive(:apply) { calls << :apply }

    result = described_class.new.call(diagram, today: reference_date)

    expect([result.class, calls]).to eq([described_class::Scene, []])
  end

  def geometry_evidence
    scene = described_class.new.call(diagram, today: reference_date)
    tasks = scene.sections.flat_map(&:tasks)
    [scene.id, scene.title.text, section_labels(scene),
     *task_geometry_evidence(tasks)]
  end

  def task_geometry_evidence(tasks)
    [tasks.map(&:status), tasks.map(&:start_date),
     tasks.map { |task| task.bar.nil? }]
  end

  def section_labels(scene)
    scene.sections.map { |section| section.label.text }
  end

  def expected_geometry
    ["plan", "Release plan", %w[Planning Shipping],
     %w[critical active done],
     [Date.new(2024, 1, 1), Date.new(2024, 1, 3),
      Date.new(2024, 1, 5)],
     [false, false, true]]
  end
end
