# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  def labels_of(*lines)
    source = "@startuml\n#{lines.join("\n")}\n@enduml\n"
    svg = REXML::Document.new(Sirena.render(source, notation: :plantuml))
    nodes = REXML::XPath.match(svg, "//g[starts-with(@id,'relation-')]/text")
    nodes.map { |node| label_from(node) }
  end

  def label_from(node)
    attrs = node.attributes
    { text: node.text, x: attrs["x"].to_f, y: attrs["y"].to_f,
      size: attrs["font-size"].to_f }
  end

  def box(label)
    x, y, size = label.values_at(:x, :y, :size)
    half = label[:text].length * size * 0.3
    [x - half, y - size, x + half, y + (size / 4)]
  end

  def overlapping?(first, second)
    a = box(first)
    b = box(second)
    a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3]
  end

  def pairs_of(labels)
    labels.combination(2)
  end

  let(:parallel) do
    labels_of("class A", "class B", "A --> B : l1", "A --> B : l2",
              "A --> B : l3")
  end

  it "keeps three labels on parallel relations apart" do
    expect(pairs_of(parallel).select { |a, b| overlapping?(a, b) }).to be_empty
  end

  it "keeps every parallel label within two lines of its edge" do
    spread = parallel.map { _1[:y] }.minmax.reduce { |lo, hi| hi - lo }
    texts = parallel.map { _1[:text] }
    expect([texts, spread < 60]).to eq([%w[l1 l2 l3], true])
  end

  it "separates labels of repeated links in a mixed diagram" do
    labels = labels_of("class A", "class B", "class C", "A <|-- B : l1",
                       "A <|-- C : l2", "A *-- C : l3")

    expect(pairs_of(labels).select { |a, b| overlapping?(a, b) }).to be_empty
  end

  it "leaves a label on the middle of a relation of its own untouched" do
    # B and C fan out in one rank below A, so both labels share a height;
    # the rank gap is the jar's 60 plus 17 for the one-line labels, which
    # puts the labels 0.35 above the jar's own (98.57), on the jar's 7 margin
    # (127.225 before the margin matched: 29 below).
    labels = labels_of("class A", "class B", "class C", "A --> B : l1",
                       "A --> C : l2")

    expect(labels.map { _1[:y] }).to eq([98.225, 98.225])
  end
end
