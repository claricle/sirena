# frozen_string_literal: true

require "spec_helper"

RSpec.describe "parse error format across every diagram type" do
  # Each source starts correctly and breaks on the line named in the second
  # column: [source, line of the break].
  broken = {
    flowchart: ["graph TD\nA-->\n", 3],
    sequence: ["sequenceDiagram\n???\n", 2],
    class_diagram: ["classDiagram\n???\n", 2],
    state_diagram: ["stateDiagram-v2\n???\n", 2],
    er_diagram: ["erDiagram\n???\n", 2],
    user_journey: ["journey\n???\n", 2],
    gantt: ["gantt\n???\n", 2],
    pie: ["pie\n???\n", 2],
    timeline: ["timeline\n:", 2],
    quadrant: ["quadrantChart\n???\n", 3],
    git_graph: ["gitGraph\n???\n", 2],
    mindmap: ["mindmap\n  root((a))\n    ::icon(", 3],
    kanban: ["kanban\n???\n", 2],
    radar: ["radar-beta\n???\n", 2],
    block: ["block-beta\n???\n", 2],
    requirement: ["requirementDiagram\n???\n", 2],
    xychart: ["xychart-beta\n???\n", 2],
    architecture: ["architecture-beta\n???\n", 2],
    sankey: ["sankey-beta\n???\n", 2],
    packet: ["packet-beta\n???\n", 2],
    treemap: ["treemap\n???\n", 2],
    c4: ["C4Context\n???\n", 2],
    info: ["info\n???\n", 2],
    error: ["error\n???\n", 2],
  }

  it "covers every registered type" do
    expect(broken.keys).to match_array(Sirena::DiagramRegistry.types)
  end

  broken.each do |type, (source, line)|
    it "names the line, column, source line and caret for #{type}" do
      parser = Sirena::DiagramRegistry.get(type)[:parser].new
      shown = source.lines[line - 1].to_s.chomp
      shown = "(end of input)" if shown.empty?

      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError,
        /\AParse error at line #{line}, column \d+:\n#{Regexp.escape(shown)}\n *\^\n/,
      )
    end
  end
end
