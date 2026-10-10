# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::ClassNamespaces do
  def parse(source)
    Sirena::Parser::ClassDiagram.new.parse("classDiagram\n#{source}\n")
  end

  let(:diagram) do
    parse("namespace Shapes {\n  class Tri\n  class Rect\n}\nclass Loose\n")
  end

  it "reads the namespace name" do
    expect(diagram.namespaces.map(&:name)).to eq(["Shapes"])
  end

  it "lists the classes declared inside, by entity id" do
    expect(diagram.namespaces.first.class_ids)
      .to eq(%w[Shapes.Tri Shapes.Rect])
  end

  it "leaves a class outside the block out of it" do
    expect(diagram.namespaces.first.class_ids).not_to include("Loose")
  end

  it "keeps a dotted namespace name whole" do
    expect(parse("namespace A.B {\n  class C\n}").namespaces.first.name)
      .to eq("A.B")
  end

  it "names a namespaced class by its own name" do
    expect(diagram.find_entity("Shapes.Tri").name).to eq("Tri")
  end

  it "names a class outside any namespace as written" do
    expect(diagram.find_entity("Loose").name).to eq("Loose")
  end

  it "counts a class that only appears in a relationship inside the block" do
    block = parse("namespace N {\n  class A\n  A --> B\n}")
    expect(block.namespaces.first.class_ids).to eq(%w[N.A N.B])
  end
end
