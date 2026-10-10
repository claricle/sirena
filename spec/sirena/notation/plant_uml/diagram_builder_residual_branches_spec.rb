# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::DiagramBuilder do
  let(:parser) { Sirena::Notation::PlantUML::Parser.new }
  let(:accepted_source) do
    <<~PUML
      @startuml
      package p {
        class A
      }
      class B
      p --> B
      A -- B
      (A, B) .. C
      @enduml
    PUML
  end

  it "keeps package relation ends and related association classes" do
    diagram = parser.parse(accepted_source)
    summary = [diagram.classes.map(&:name), diagram.relations.map(&:left),
               diagram.junctions.map(&:owner)]

    expect(summary).to eq([%w[A B C], %w[p A], %w[C]])
  end

  {
    "package p {\nclass A\n}\npackage p {\nclass B\n}" =>
      /package declared twice/,
    "package p {\n}" => /empty package/,
    "package a {\npackage x.y {\nclass A\n}\n}\n" \
    "package x.z {\nclass B\n}" => /shared by two packages/,
    "class A $x\nnote right of A : hi\nhide $x" =>
      /hide of a class with a note/,
    "class A\nclass B\n(A, B) .. C" =>
      /association class without its relation/,
    "package p {\nclass A\n}\nclass p" => /class named like a package/,
    "A --> B\npackage p {\nclass A\n}" => /more than one place/,
    "package p {\nA --> B\n}" => /class first mentioned in a package/,
  }.each do |body, message|
    it "refuses #{message.source}" do
      source = "@startuml\n#{body}\n@enduml\n"

      expect { parser.parse(source) }
        .to raise_error(Sirena::Notation::PlantUML::UnsupportedConstructError,
                        message)
    end
  end

  it "refuses a note on an unknown class" do
    source = "@startuml\nnote right of Missing : text\n@enduml\n"

    expect { parser.parse(source) }
      .to raise_error(Sirena::Parser::ParseError, /Missing.*not declared/)
  end
end
