# frozen_string_literal: true

require "sirena"

# Every diagram in a `[source,mermaid]` block on the docs pages is rendered
# through Sirena.render. A diagram that does not render is listed in
# DocMermaidSpec::EXPECTED_FAILURES with the reason and the error it raises;
# the list can only shrink: an entry that now renders fails the suite.
module DocMermaidSpec
  PARSE = Sirena::Parser::ParseError
  DETECT = Sirena::Engine::DiagramTypeError

  # Reasons:
  #   :fragment         shows one statement, with no diagram header, so
  #                     Sirena cannot tell the diagram type
  #   :placeholder      contains <...> or ... where the reader fills in content
  #   :mermaid_rejects  mermaid-cli 11 renders an error diagram for it
  #                     (the docs example is wrong, not Sirena)
  #   :sirena_gap       mermaid-cli renders it and Sirena raises
  EXPECTED_FAILURES = {
    "docs/_diagram_types/c4-diagram.adoc" => {
      "Basic Relationship #2" => [:fragment, DETECT],
      "Combined Attributes #1" => [:mermaid_rejects, PARSE],
    },
    "docs/_diagram_types/class-diagram.adoc" => {
      "Diagram declaration #1" => [:placeholder, PARSE],
      "Attributes #1" => [:fragment, DETECT],
      "Attributes #2" => [:fragment, DETECT],
      "Attributes #3" => [:fragment, DETECT],
      "Methods #1" => [:fragment, DETECT],
      "Methods #2" => [:fragment, DETECT],
      "Relationship labels #1" => [:fragment, DETECT],
      "Bidirectional associations #1" => [:fragment, DETECT],
      "Cardinality #1" => [:fragment, DETECT],
      "Generics #1" => [:fragment, DETECT],
      "Abstract classes #1" => [:fragment, DETECT],
      "Interfaces #1" => [:fragment, DETECT],
      "Stereotypes #1" => [:fragment, DETECT],
      "Annotations #1" => [:fragment, DETECT],
      "Method parameters #1" => [:fragment, DETECT],
      "Multiple methods and attributes #1" => [:fragment, DETECT],
      "Static members #1" => [:fragment, DETECT],
      "Keep classes focused #1" => [:fragment, DETECT],
      "Use meaningful names #1" => [:fragment, DETECT],
      "Show relevant details #1" => [:fragment, DETECT],
    },
    "docs/_diagram_types/er-diagram.adoc" => {
      "Diagram declaration #1" => [:placeholder, PARSE],
      "Use appropriate cardinality #1" => [:fragment, DETECT],
      "Use consistent naming #1" => [:fragment, DETECT],
    },
    "docs/_diagram_types/flowchart.adoc" => {
      "Diagram declaration #1" => [:placeholder, PARSE],
      "Diagram declaration #2" => [:placeholder, PARSE],
      "Edge labels #1" => [:fragment, DETECT],
      "Subgraphs #1" => [:fragment, DETECT],
      "Subgraphs #2" => [:fragment, DETECT],
    },
    "docs/_diagram_types/gantt-chart.adoc" => {
      "Diagram declaration #1" => [:placeholder, PARSE],
      "Basic task with dates and duration #1" => [:fragment, DETECT],
      "Basic task with dates and duration #2" => [:fragment, DETECT],
      "Task with start and end dates #1" => [:fragment, DETECT],
      "Task with start and end dates #2" => [:fragment, DETECT],
      "Task with dependencies #1" => [:fragment, DETECT],
      "Task with dependencies #2" => [:fragment, DETECT],
      "Task with status tags #1" => [:fragment, DETECT],
      "Organize with sections #1" => [:placeholder, PARSE],
    },
    "docs/_diagram_types/git-graph.adoc" => {
      "Diagram declaration #1" => [:placeholder, PARSE],
      "Orientation #1" => [:placeholder, PARSE],
      "Commits #1" => [:fragment, DETECT],
      "Commit with options #1" => [:fragment, DETECT],
      "Creating a branch #1" => [:fragment, DETECT],
      "Branch with ordering #1" => [:fragment, DETECT],
      "Checkout #1" => [:fragment, DETECT],
      "Switch #1" => [:fragment, DETECT],
      "Merge operations #1" => [:fragment, DETECT],
      "Merge with options #1" => [:fragment, DETECT],
      "Cherry-pick operations #1" => [:fragment, DETECT],
      "Cherry-pick with parent #1" => [:fragment, DETECT],
      "Cherry-pick with tag #1" => [:fragment, DETECT],
    },
    "docs/_diagram_types/kanban-diagram.adoc" => {
      "Card Metadata #1" => [:fragment, DETECT],
      "Supported Metadata Fields #1" => [:mermaid_rejects, PARSE],
      "Complex Workflow #1" => [:mermaid_rejects, PARSE],
    },
    "docs/_diagram_types/packet-diagram.adoc" => {
      "Diagram declaration #1" => [:placeholder, PARSE],
      "Title #1" => [:sirena_gap, PARSE],
      "Field definitions #1" => [:fragment, DETECT],
      "TCP header structure #1" => [:sirena_gap, PARSE],
      "Include title for context #1.1" => [:placeholder, PARSE],
    },
    "docs/_diagram_types/pie-chart.adoc" => {
      "Case-insensitive syntax #1" => [:mermaid_rejects, PARSE],
    },
    "docs/_diagram_types/quadrant-chart.adoc" => {
      "Coordinates #1" => [:mermaid_rejects, PARSE],
    },
    "docs/_diagram_types/radar-chart.adoc" => {
      "Diagram declaration #1" => [:placeholder, PARSE],
      "Value normalization #1" => [:mermaid_rejects, PARSE],
      "Set explicit ranges #1" => [:mermaid_rejects, PARSE],
      "Use consistent scales #1.2" => [:mermaid_rejects, PARSE],
    },
    "docs/_diagram_types/requirement-diagram.adoc" => {
      "Relationship syntax #1" => [:fragment, DETECT],
    },
    "docs/_diagram_types/sankey-diagram.adoc" => {
      "Diagram declaration #1" => [:placeholder, PARSE],
      "Flow syntax #1" => [:fragment, DETECT],
      "Flow syntax #2" => [:fragment, DETECT],
      "Node label declarations (optional) #1" => [:fragment, DETECT],
      "Node label declarations (optional) #2" => [:fragment, DETECT],
      "Budget allocation example #1" => [:sirena_gap, PARSE],
      "Choose meaningful node IDs #1" => [:fragment, DETECT],
      "Balance your flows #1" => [:fragment, DETECT],
    },
    "docs/_diagram_types/sequence-diagram.adoc" => {
      "Diagram declaration #1" => [:placeholder, PARSE],
      "Notes #1" => [:fragment, DETECT],
      "Loops #1" => [:fragment, DETECT],
      "Alt (alternative paths) #1" => [:fragment, DETECT],
      "Opt (optional) #1" => [:fragment, DETECT],
      "Par (parallel) #1" => [:fragment, DETECT],
      "Critical (critical region) #1" => [:fragment, DETECT],
      "Break #1" => [:fragment, DETECT],
      "Boxes #1" => [:fragment, DETECT],
      "Boxes #2" => [:fragment, DETECT],
      "Keep participants minimal #1.1" => [:mermaid_rejects, PARSE],
      "Keep participants minimal #1.2" => [:mermaid_rejects, PARSE],
    },
    "docs/_diagram_types/state-diagram.adoc" => {
      "Diagram declaration #1" => [:placeholder, PARSE],
      "Scale #1" => [:sirena_gap, PARSE],
      "Complex state machine with multiple features #1" => [:sirena_gap, PARSE],
    },
    "docs/_diagram_types/timeline.adoc" => {
      "Event syntax #1" => [:fragment, DETECT],
      "Event syntax #2" => [:fragment, DETECT],
      "Event syntax #3" => [:fragment, DETECT],
    },
    "docs/_diagram_types/treemap-diagram.adoc" => {
      "Diagram declaration #1" => [:placeholder, PARSE],
      "Diagram declaration #2" => [:placeholder, PARSE],
      "Node definitions #1" => [:fragment, DETECT],
      "Include titles #1.1" => [:placeholder, PARSE],
      "Include titles #1.2" => [:placeholder, PARSE],
    },
    "docs/_diagram_types/user-journey.adoc" => {
      "Diagram declaration #1" => [:placeholder, PARSE],
      "Sections #1" => [:sirena_gap, PARSE],
      "Tasks #1" => [:fragment, DETECT],
      "Organize with meaningful sections #1.1" => [:placeholder, PARSE],
      "Organize with meaningful sections #1.2" => [:placeholder, PARSE],
      "Keep journeys focused #1.1" => [:placeholder, PARSE],
      "Keep journeys focused #1.2" => [:placeholder, PARSE],
    },
  }.freeze

  REASONS = %i[fragment placeholder mermaid_rejects sirena_gap].freeze

  def self.expected(diagram)
    EXPECTED_FAILURES.dig(diagram.file, diagram.key)
  end
end

RSpec.describe DocMermaidSpec do
  let(:diagrams) { DocMermaidBlocks.diagrams }

  it "extracts every [source,mermaid] block on the docs pages" do
    extracted = DocMermaidBlocks.block_count
    expect(extracted).to eq(DocMermaidBlocks.marker_count)
  end

  it "gives every diagram a unique key within its page" do
    keys = diagrams.map { |d| [d.file, d.key] }
    expect(keys.uniq).to eq(keys)
  end

  it "lists only diagrams that exist, with a known reason" do
    listed = DocMermaidSpec::EXPECTED_FAILURES.flat_map { |f, e| e.keys.map { |k| [f, k] } }
    existing = diagrams.map { |d| [d.file, d.key] }
    expect(listed - existing).to eq([])
    expect(DocMermaidSpec::EXPECTED_FAILURES.values.flat_map(&:values).map(&:first) - DocMermaidSpec::REASONS)
      .to eq([])
  end

  DocMermaidBlocks.diagrams.each do |diagram|
    if described_class.expected(diagram)
      it "#{diagram.file} #{diagram.key} still fails as #{described_class.expected(diagram).first}" do
        expect { Sirena.render(diagram.source) }.to raise_error(described_class.expected(diagram).last)
      end
    else
      it "#{diagram.file} #{diagram.key} renders an SVG document" do
        expect(Sirena.render(diagram.source)).to match(/\A\s*<svg\b.*<\/svg>\s*\z/m)
      end
    end
  end
end
