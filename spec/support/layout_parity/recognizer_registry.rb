# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Maps every registered Mermaid type to its shared SVG recognizer and the
    # historical fixture directory that stores that type's references.
    class RecognizerRegistry
      Entry = Data.define(:type, :recognizer, :reference_directory)

      RECOGNIZER_NAMES = {
        architecture: "ArchitectureRecognizer",
        block: "BlockRecognizer",
        c4: "C4Recognizer",
        class_diagram: "ClassDiagramRecognizer",
        er_diagram: "ErDiagramRecognizer",
        error: "ErrorRecognizer",
        flowchart: "FlowchartRecognizer",
        gantt: "GanttRecognizer",
        git_graph: "GitGraphRecognizer",
        info: "InfoRecognizer",
        kanban: "KanbanRecognizer",
        mindmap: "MindmapRecognizer",
        packet: "PacketRecognizer",
        pie: "PieRecognizer",
        quadrant: "QuadrantRecognizer",
        radar: "RadarRecognizer",
        requirement: "RequirementRecognizer",
        sankey: "SankeyRecognizer",
        sequence: "SequenceRecognizer",
        state_diagram: "StateDiagramRecognizer",
        timeline: "TimelineRecognizer",
        treemap: "TreemapRecognizer",
        user_journey: "UserJourneyRecognizer",
        xychart: "XyChartRecognizer",
      }.freeze

      REFERENCE_DIRECTORIES = {
        class_diagram: "class",
        er_diagram: "er",
        git_graph: "gitgraph",
        state_diagram: "state",
      }.freeze

      def self.fetch(type)
        key = type.to_sym
        name = RECOGNIZER_NAMES.fetch(key) do
          raise KeyError, "no parity recognizer for #{type}"
        end
        recognizer = LayoutParity.const_get(name, false).new
        directory = REFERENCE_DIRECTORIES.fetch(key, key.to_s)

        Entry.new(type: key, recognizer: recognizer,
                  reference_directory: directory)
      end
    end
  end
end
