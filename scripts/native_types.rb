# frozen_string_literal: true

module NativeTypes
  # Corpus directory => [require path, parser class name]; one row per
  # Mermaid diagram type sirena parses.
  TYPES = {
    "architecture" => ["architecture", "Architecture"],
    "block" => ["block", "Block"],
    "c4" => ["c4", "C4"],
    "class_diagram" => ["class_diagram", "ClassDiagram"],
    "er_diagram" => ["er_diagram", "ErDiagram"],
    "flowchart" => ["flowchart", "Flowchart"],
    "gantt" => ["gantt", "Gantt"],
    "gitgraph" => ["git_graph", "GitGraph"],
    "info" => ["info", "Info"],
    "kanban" => ["kanban", "Kanban"],
    "mindmap" => ["mindmap", "Mindmap"],
    "packet" => ["packet", "Packet"],
    "pie" => ["pie", "Pie"],
    "quadrant" => ["quadrant", "Quadrant"],
    "radar" => ["radar", "Radar"],
    "requirement" => ["requirement", "Requirement"],
    "sankey" => ["sankey", "Sankey"],
    "sequence" => ["sequence", "Sequence"],
    "state_diagram" => ["state_diagram", "StateDiagram"],
    "timeline" => ["timeline", "Timeline"],
    "treemap" => ["treemap", "Treemap"],
    "user_journey" => ["user_journey", "UserJourney"],
    "xychart" => ["xy_chart", "XyChart"],
  }.freeze
end
