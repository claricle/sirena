# frozen_string_literal: true

require "json"

# Renders the per-type pass table in docs/_pages/compatibility.adoc from
# scoreboard/corpus.json. Only the region between the BEGIN/END markers is
# owned by this task; `rake docs:compatibility` rewrites it, and
# spec/tasks/compatibility_spec.rb fails when the page and scoreboard differ.
module Sirena
  module DocsCompatibility
    ROOT = File.expand_path("..", __dir__)
    PAGE_PATH = File.join(ROOT, "docs/_pages/compatibility.adoc")
    SCOREBOARD_PATH = File.join(ROOT, "scoreboard/corpus.json")
    BEGIN_MARKER = "// BEGIN GENERATED: rake docs:compatibility"
    END_MARKER = "// END GENERATED"

    # label, syntax keyword(s), corpus directories counted under that label.
    # The corpus has two directories for some types (e.g. class, class_diagram).
    TYPES = [
      ["Architecture", "architecture-beta", %w[architecture]],
      ["Block", "block-beta", %w[block]],
      ["C4", "C4 (all 5 subtypes)", %w[c4]],
      ["Class Diagram", "classDiagram", %w[class class_diagram]],
      ["ER Diagram", "erDiagram", %w[er er_diagram]],
      ["Error Diagram", "error", %w[error]],
      ["Flowchart", "graph, flowchart", %w[flowchart]],
      ["Gantt Chart", "gantt", %w[gantt]],
      ["Git Graph", "gitGraph", %w[git gitgraph]],
      ["Info Diagram", "info", %w[info]],
      ["Kanban", "kanban", %w[kanban]],
      ["Mindmap", "mindmap", %w[mindmap]],
      ["Packet Diagram", "packet", %w[packet]],
      ["Pie Chart", "pie", %w[pie]],
      ["Quadrant Chart", "quadrantChart", %w[quadrant]],
      ["Radar Chart", "radar", %w[radar]],
      ["Requirement Diagram", "requirementDiagram", %w[requirement]],
      ["Sankey", "sankey-beta", %w[sankey]],
      ["Sequence Diagram", "sequenceDiagram", %w[sequence]],
      ["State Diagram", "stateDiagram-v2", %w[state state_diagram]],
      ["Timeline", "timeline", %w[timeline]],
      ["Treemap", "treemap", %w[treemap]],
      ["User Journey", "journey", %w[user_journey]],
      ["XY Chart", "xychart-beta", %w[xychart]],
    ].freeze

    OPEN = Regexp.escape(BEGIN_MARKER)
    CLOSE = Regexp.escape(END_MARKER)
    REGION = /^#{OPEN}\n.*?^#{CLOSE}$/m

    module_function

    # label => [passing, total], counting only cases mmdc accepted ("valid").
    def valid_by_dir(scoreboard_path)
      rows = JSON.parse(File.read(scoreboard_path))
      rows.select { |row| row["verdict"] == "valid" }
        .group_by { |row| row["case"].split("/").first }
    end

    def counts(scoreboard_path = SCOREBOARD_PATH)
      by_dir = valid_by_dir(scoreboard_path)
      TYPES.to_h do |label, _syntax, dirs|
        cases = by_dir.values_at(*dirs).compact.flatten
        [label, [cases.count { |row| row["pass"] }, cases.size]]
      end
    end

    def rate(passing, total)
      total.zero? ? "n/a" : format("%.1f%%", passing * 100.0 / total)
    end

    INTRO = [
      "Generated from `scoreboard/corpus.json`. Counts cover only corpus",
      "cases that mmdc itself accepts (oracle verdict `valid`); extraction",
      "artifacts and cases mmdc rejects are excluded from the denominator.",
      "", "[cols=\"3,3,2,2\"]", "|===", "|Type |Syntax |Passing |Rate", ""
    ].freeze

    def row(label, syntax, passing, total)
      "|#{label}\n|`#{syntax}`\n|#{passing}/#{total}\n" \
        "|#{rate(passing, total)}\n"
    end

    def region(scoreboard_path = SCOREBOARD_PATH)
      counts = counts(scoreboard_path)
      rows = TYPES.map do |label, syntax, _dirs|
        row(label, syntax, *counts.fetch(label))
      end
      [BEGIN_MARKER, *INTRO, *rows, "|===", END_MARKER].join("\n")
    end

    def splice(text, new_region)
      raise "no generated-region markers" unless text.match?(REGION)

      text.sub(REGION) { new_region }
    end

    def current_page
      splice(File.read(PAGE_PATH), region)
    end

    def write!
      File.write(PAGE_PATH, current_page)
    end
  end
end

namespace :docs do
  desc "Regenerate the table in docs/_pages/compatibility.adoc"
  task :compatibility do
    Sirena::DocsCompatibility.write!
  end
end
