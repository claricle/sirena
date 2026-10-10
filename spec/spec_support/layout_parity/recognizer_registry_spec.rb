# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::RecognizerRegistry do
  let(:expected) do
    {
      architecture: ["ArchitectureRecognizer", "architecture"],
      block: ["BlockRecognizer", "block"],
      c4: ["C4Recognizer", "c4"],
      class_diagram: ["ClassDiagramRecognizer", "class"],
      er_diagram: ["ErDiagramRecognizer", "er"],
      error: ["ErrorRecognizer", "error"],
      flowchart: ["FlowchartRecognizer", "flowchart"],
      gantt: ["GanttRecognizer", "gantt"],
      git_graph: ["GitGraphRecognizer", "gitgraph"],
      info: ["InfoRecognizer", "info"],
      kanban: ["KanbanRecognizer", "kanban"],
      mindmap: ["MindmapRecognizer", "mindmap"],
      packet: ["PacketRecognizer", "packet"],
      pie: ["PieRecognizer", "pie"],
      quadrant: ["QuadrantRecognizer", "quadrant"],
      radar: ["RadarRecognizer", "radar"],
      requirement: ["RequirementRecognizer", "requirement"],
      sankey: ["SankeyRecognizer", "sankey"],
      sequence: ["SequenceRecognizer", "sequence"],
      state_diagram: ["StateDiagramRecognizer", "state"],
      timeline: ["TimelineRecognizer", "timeline"],
      treemap: ["TreemapRecognizer", "treemap"],
      user_journey: ["UserJourneyRecognizer", "user_journey"],
      xychart: ["XyChartRecognizer", "xychart"],
    }
  end

  it "maps every Mermaid type to its recognizer and reference directory" do
    expect(actual_mapping).to eq(expected)
  end

  it "rejects a type without a parity recognizer" do
    expect { described_class.fetch(:not_registered) }
      .to raise_error(KeyError, "no parity recognizer for not_registered")
  end

  it "carries the type measurement policy with each recognizer" do
    entry = described_class.fetch(:quadrant)

    expect(entry.measurement_policy)
      .to equal(SpecSupport::LayoutParity::MeasurementPolicy.for(:quadrant))
  end

  def actual_mapping
    Sirena::Notation::Mermaid.types.to_h do |type|
      entry = described_class.fetch(type)
      [type, [entry.recognizer.class.name.split("::").last,
              entry.reference_directory]]
    end
  end
end
