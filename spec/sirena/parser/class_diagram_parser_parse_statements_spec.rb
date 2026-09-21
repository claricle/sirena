# frozen_string_literal: true

require "spec_helper"

# Statement-level constructs that mermaid's class grammar accepts and that
# the model does not keep: click, style, cssClass, classDef, accessibility
# text and notes. Each one has to parse without inventing a class.
RSpec.describe Sirena::Parser::ClassDiagramParser, "#parse statements" do
  let(:parser) { described_class.new }

  def entity_ids(source)
    parser.parse(source).entities.map(&:id)
  end

  {
    "click href with tooltip" =>
      'click Shape href "https://www.github.com" "A tooltip"',
    "click href with target" => 'click Shape href "https://x.test" _self',
    "click call with tooltip" =>
      'click Shape call clickByClass(123) "A tooltip"',
    "click call with args" => "click Shape call functionCall(a, b)",
    "click href without a url (corpus artifact)" => "click Shape href",
    "style" => "style Shape fill:#f9f,stroke:#333,stroke-width:8px",
    "cssClass on one class" => 'cssClass "Shape" pink',
    "cssClass on a list" => 'cssClass "Shape,Other" pink',
    "classDef" => "classDef pink fill:#f9f,stroke:#333",
    "classDef default" => "classDef default color:#f1e",
    "accTitle" => "accTitle: My Title",
    "single-line accDescr" => "accDescr: My Description",
    "multiline accDescr" => "accDescr {\n  a multi\n  line description\n}",
    "general note" => 'note "This is a general note"',
    "note for a class" => 'note for Shape "About the shape"',
    "note with quotes inside markup" =>
      %(note for Shape "<a href='x' target="_blank">y</a>"),
  }.each do |name, statement|
    it "parses #{name} without adding a class" do
      source = "classDiagram\nclass Shape\n#{statement}\n"

      expect(entity_ids(source)).to eq(["Shape"])
    end
  end

  it "does not read a statement keyword as a class name" do
    expect(entity_ids("classDiagram\nclass Shape\nstyle Shape fill:#f9f\n"))
      .not_to include("style")
  end

  it "still parses classes whose name starts with a statement keyword" do
    source = "classDiagram\nnotebook --> clicker\nstyleguide\n"

    expect(entity_ids(source)).to eq(%w[notebook clicker styleguide])
  end

  describe "direction inside the diagram" do
    it "sets the direction from a direction statement" do
      diagram = parser.parse("classDiagram\ndirection RL\nclass A\n")

      expect(diagram.direction).to eq("RL")
    end

    it "lets the statement override the header direction" do
      diagram = parser.parse("classDiagram TB\ndirection LR\nclass A\n")

      expect(diagram.direction).to eq("LR")
    end

    it "rejects an unknown direction" do
      expect { parser.parse("classDiagram\ndirection XX\nclass A\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  it "renders a diagram holding only accessibility text" do
    source = "classDiagram\naccTitle: My Title\naccDescr {\n  text\n}\n"

    expect(Sirena.render(source)).to start_with("<svg").or start_with("<?xml")
  end

  it "renders a diagram with accessibility text and a class" do
    source = "classDiagram\naccTitle: My Title\naccDescr: text\nclass A\n"

    expect(Sirena.render(source)).to start_with("<svg").or start_with("<?xml")
  end
end
