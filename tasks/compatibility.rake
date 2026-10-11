# frozen_string_literal: true

require "json"

# Renders the per-type pass table in docs/_pages/compatibility.adoc from
# scoreboard/corpus.json. Only the region between the BEGIN/END markers is
# owned by this task; `rake docs:compatibility` rewrites it, and
# spec/sirena/docs_compatibility_spec.rb fails when the page and
# scoreboard differ.
module Sirena
  module DocsCompatibility
    ROOT = File.expand_path("..", __dir__)
    PAGE_PATH = File.join(ROOT, "docs/_pages/compatibility.adoc")
    SCOREBOARD_PATH = File.join(ROOT, "scoreboard/corpus.json")
    PLANTUML_PAGE_PATH = File.join(ROOT, "docs/_pages/comparison.adoc")
    PLANTUML_SCOREBOARD_PATH = File.join(ROOT, "scoreboard/plantuml.json")
    BEGIN_MARKER = "// BEGIN GENERATED: rake docs:compatibility"
    END_MARKER = "// END GENERATED"
    PLANTUML_BEGIN_MARKER =
      "// BEGIN GENERATED: rake docs:compatibility plantuml"
    PLANTUML_END_MARKER =
      "// END GENERATED: rake docs:compatibility plantuml"

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

    TYPE_PAGES = {
      "C4" => ["c4", "c4-diagram.adoc"],
      "Pie Chart" => ["pie", "pie-chart.adoc"],
      "Quadrant Chart" => ["quadrant", "quadrant-chart.adoc"],
      "Timeline" => ["timeline", "timeline.adoc"],
    }.freeze
    VERDICT_ORDER = %w[artifact invalid unknown].freeze

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

    def cases_for(label, scoreboard_path = SCOREBOARD_PATH)
      _label, _syntax, dirs = TYPES.find { |row| row.first == label }
      by_dir = JSON.parse(File.read(scoreboard_path))
        .group_by { |row| row["case"].split("/").first }
      by_dir.values_at(*dirs).compact.flatten
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

    def type_page_path(label)
      File.join(ROOT, "docs/_diagram_types", TYPE_PAGES.fetch(label).last)
    end

    def type_page_marker(label, edge)
      id = TYPE_PAGES.fetch(label).first
      "// #{edge} GENERATED: rake docs:compatibility #{id}"
    end

    def type_page_region(label, scoreboard_path = SCOREBOARD_PATH)
      cases = cases_for(label, scoreboard_path)
      valid = cases.select { |row| row["verdict"] == "valid" }
      passing = valid.count { |row| row["pass"] }
      outside = outside_denominator(cases)

      [
        type_page_marker(label, "BEGIN"),
        "* Oracle-valid corpus coverage: `#{passing}/#{valid.size} passing " \
        "(#{rate(passing, valid.size)})`.",
        "* Outside the compatibility denominator: #{outside}.",
        "* Generated from `scoreboard/corpus.json` by " \
        "`bundle exec rake docs:compatibility`.",
        type_page_marker(label, "END"),
      ].join("\n")
    end

    def outside_denominator(cases)
      by_verdict = cases.reject { |row| row["verdict"] == "valid" }
        .group_by { |row| row["verdict"] }
      summaries = VERDICT_ORDER.filter_map do |verdict|
        verdict_summary(verdict, by_verdict[verdict])
      end
      summaries.empty? ? "no other verdict cases" : summaries.join("; ")
    end

    def verdict_summary(verdict, rows)
      return unless rows

      passing = rows.count { |row| row["pass"] }
      "#{passing}/#{rows.size} `#{verdict}` cases currently render"
    end

    def plantuml_region(scoreboard_path = PLANTUML_SCOREBOARD_PATH)
      counts = plantuml_counts(JSON.parse(File.read(scoreboard_path)))
      claim = "**Syntax Compatibility:** Sirena renders PlantUML class and " \
              "sequence diagrams when started with `--require " \
              "sirena/notation/plantuml` (`scoreboard/plantuml.json`: " \
              "#{counts.join(', ')} oracle-valid cases). Other PlantUML " \
              "diagram types are not supported."
      [PLANTUML_BEGIN_MARKER, claim, PLANTUML_END_MARKER].join("\n")
    end

    def plantuml_counts(rows)
      %w[class sequence].map do |type|
        row = rows.find { |candidate| candidate["type"] == type }
        raise "no PlantUML #{type} scoreboard row" unless row

        "#{type} #{row.fetch('passing')}/#{row.fetch('oracle_valid')}"
      end
    end

    def splice(text, new_region)
      raise "no generated-region markers" unless text.match?(REGION)

      text.sub(REGION) { new_region }
    end

    def current_page
      splice(File.read(PAGE_PATH), region)
    end

    def current_type_page(label)
      path = type_page_path(label)
      begin_marker = Regexp.escape(type_page_marker(label, "BEGIN"))
      end_marker = Regexp.escape(type_page_marker(label, "END"))
      generated_region = /^#{begin_marker}\n.*?^#{end_marker}$/m
      text = File.read(path)
      unless text.match?(generated_region)
        raise "no generated-region markers in #{path}"
      end

      text.sub(generated_region) { type_page_region(label) }
    end

    def current_plantuml_page
      open = Regexp.escape(PLANTUML_BEGIN_MARKER)
      close = Regexp.escape(PLANTUML_END_MARKER)
      generated_region = /^#{open}\n.*?^#{close}$/m
      text = File.read(PLANTUML_PAGE_PATH)
      unless text.match?(generated_region)
        raise "no generated PlantUML region in #{PLANTUML_PAGE_PATH}"
      end

      text.sub(generated_region) { plantuml_region }
    end

    def write!
      File.write(PAGE_PATH, current_page)
      TYPE_PAGES.each_key do |label|
        File.write(type_page_path(label), current_type_page(label))
      end
      File.write(PLANTUML_PAGE_PATH, current_plantuml_page)
    end
  end
end

namespace :docs do
  desc "Regenerate the table in docs/_pages/compatibility.adoc"
  task :compatibility do
    Sirena::DocsCompatibility.write!
  end
end
