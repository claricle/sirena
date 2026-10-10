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
      .to eq(%w[Tri Rect])
  end

  it "leaves a class outside the block out of it" do
    expect(diagram.namespaces.first.class_ids).not_to include("Loose")
  end

  it "keeps a dotted namespace name whole" do
    expect(parse("namespace A.B {\n  class C\n}").namespaces.first.name)
      .to eq("A.B")
  end

  it "gives a namespaced class its plain id and name" do
    expect(diagram.find_entity("Tri").name).to eq("Tri")
  end

  it "names a class outside any namespace as written" do
    expect(diagram.find_entity("Loose").name).to eq("Loose")
  end

  it "counts a class that only appears in a relationship inside the block" do
    block = parse("namespace N {\n  class A\n  A --> B\n}")
    expect(block.namespaces.first.class_ids).to eq(%w[A B])
  end

  it "makes a relationship written outside the block reuse the class" do
    source = "A1 --> B1\nnamespace A {\n  class A1\n}\n" \
             "namespace B {\n  class B1\n}\n"
    expect(parse(source).entities.map(&:id)).to eq(%w[A1 B1])
  end

  it "keeps one class declared in two blocks in the last one only" do
    source = "namespace N1 { class C }\nnamespace N2 { class C }"
    expect(parse(source).namespaces.map(&:class_ids))
      .to eq([[], %w[C]])
  end

  it "makes one entity of a class declared in two blocks" do
    source = "namespace N1 { class C }\nnamespace N2 { class C }"
    expect(parse(source).entities.map(&:id)).to eq(%w[C])
  end
end
