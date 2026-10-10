# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::DiagramBuilder do
  let(:parse) do
    lambda do |body|
      Sirena::Notation::PlantUML::Parser.new
        .parse("@startuml\n#{body}@enduml\n")
    end
  end

  it "opens a shared parent namespace once for two dotted packages" do
    source = "package a.b {\nclass X\n}\npackage a.c {\nclass Y\n}\n"

    expect(parse.call(source).packages.map(&:id)).to eq(%w[a a.b a.c])
  end

  it "accepts a relation between known classes inside a package" do
    source = "class A\nclass B\npackage p {\nclass C\nA --> B\n}\n"

    expect(parse.call(source).relations.size).to eq(1)
  end
end
