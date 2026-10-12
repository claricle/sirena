# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:source) do
    <<~PLANTUML
      @startuml
      !pragma layout smetana
      class A
      class B $hidden
      A --> B
      A --> C
      hide $hidden
      @enduml
    PLANTUML
  end

  let(:restored_facts) do
    diagram = Sirena::Notation::PlantUML::Parser.new.parse(source)
    graph = Sirena::Notation::PlantUML::IRAdapter.call(diagram)
    restored = Sirena::Notation::PlantUML::IRReader.call(graph)
    facts = restored.relations.map do |relation|
      [[relation.left, relation.right], relation.layout_only?]
    end
    [restored.classes.map(&:name), facts]
  end

  let(:layout_facts) do
    document = REXML::Document.new(Sirena.render(source, notation: :plantuml))
    dimensions = %w[x y width height]
    boxes = %w[A B C].to_h do |name|
      rect = REXML::XPath.first(document, "//g[@id='class-#{name}']/rect")
      [name, dimensions.map { |key| rect.attributes[key].to_f }]
    end
    ax, ay, aw, ah = boxes.fetch("A")
    bx, by, = boxes.fetch("B")
    cx, cy, cw, = boxes.fetch("C")
    path = "//g[starts-with(@id, 'relation-')]"
    relation_ids = REXML::XPath.match(document, path)
      .map { |group| group.attributes["id"] }
    leaves_center = (bx + cx + cw) / 2
    [by == cy, ay + ah < by, ax + (aw / 2) == leaves_center,
     relation_ids]
  end

  it "carries the hidden relation through the IR as layout-only" do
    expect(restored_facts)
      .to eq([%w[A B C], [[%w[A B], true], [%w[A C], false]]])
  end

  it "places both leaves below their shared root but draws only one edge" do
    expect(layout_facts).to eq([true, true, true, ["relation-1"]])
  end

  it "keeps the ordinary dot hide behavior" do
    ordinary = source.sub("!pragma layout smetana\n", "")
    diagram = Sirena::Notation::PlantUML::Parser.new.parse(ordinary)
    facts = [diagram.classes.map(&:name), diagram.relations.map(&:layout_only?)]

    expect(facts).to eq([%w[A C], [false]])
  end
end
