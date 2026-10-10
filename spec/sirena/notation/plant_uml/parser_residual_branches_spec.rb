# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Parser do
  let(:parser) { described_class.new }
  let(:feature_source) do
    <<~PUML
      @startuml
      !pragma layout smetana
      package p {
        class A {
          int count
          void run(int value)
          {method} operation
          {field} +visible
          {static} cached
        }
        class B
        A -- B
        (A, B) .. C
        note right of A : inline
        note left of A
          block
        end note
      }
      package q <<frame>> {
        class D
      }
      hide $unused
      @enduml
    PUML
  end
  let(:diagram) { parser.parse(feature_source) }
  let(:member_summary) do
    diagram.classes.first.body.map do |member|
      [member.kind, member.name, member.type]
    end
  end

  it "records a directive and both supported package shapes" do
    expect([diagram.directives, diagram.packages.map(&:shape)])
      .to eq([["!pragma layout smetana"], %i[folder frame]])
  end

  it "records an association class junction" do
    expect(diagram.junctions.first)
      .to have_attributes(from: "A", to: "B", owner: "C")
  end

  it "reads inline and block notes" do
    expect(diagram.notes.map(&:lines)).to eq([["inline"], ["block"]])
  end

  it "reads typed and modified members" do
    expect(member_summary).to eq(
      [[:field, "count", "int"], [:method, "run", "void"],
       [:method, "operation", nil], [:field, "visible", nil],
       [:field, "cached", nil]],
    )
  end

  it "hides a class carrying the named tag" do
    source = "@startuml\nclass A\nclass B $gone\nhide $gone\n@enduml\n"

    expect(parser.parse(source).classes.map(&:name)).to eq(["A"])
  end

  {
    "package p <<cloud>> {\nclass A\n}" => /package stereotype/,
    "class A\nnote right of A::x : inline" => /note/,
    "class A\nA <-> B" => /relation <-> arrow/,
    "class A\nnote right of A\n' comment\nend note" => /comment in a note/,
    "class A {\n{static} +run() junk\n}" => /member/,
    "class A {\n{static} int value\n}" => /member/,
    "class A {\n{field} run()\n}" => /member/,
  }.each do |body, message|
    it "refuses #{body.lines.first.strip.inspect}" do
      source = "@startuml\n#{body}\n@enduml\n"

      expect { parser.parse(source) }
        .to raise_error(Sirena::Notation::PlantUML::UnsupportedConstructError,
                        message)
    end
  end

  {
    "package p {\nclass A" => /package opened on line 2/,
    "class A\nnote right of A\n@enduml" => /note opened on line 3/,
  }.each do |body, message|
    it "reports the unclosed #{body.lines.last.strip.inspect}" do
      source = "@startuml\n#{body}\n@enduml\n"

      expect { parser.parse(source) }
        .to raise_error(Sirena::Parser::ParseError, message)
    end
  end
end
