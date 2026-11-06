# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# A link label sits beside its own line and must also clear the lines of
# the links next to it, as the JAR keeps them apart.
RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  let(:class_source) do
    <<~PUML
      @startuml
      class foo
      class bar
      foo --> bar : ￿
      foo -[#red,thickness=1]-> bar1 : [#red,1]
      foo -[#red,dashed,thickness=2]-> bar2 : [#red,dashed,2]
      foo -[#green,dashed,thickness=4]-> bar3 : [#green,dashed,4]
      foo -[#blue,dotted,thickness=8]-> bar4 : [blue,dotted,8]
      foo -[#blue,plain,thickness=16]-> bar5 : [blue,plain,16]
      @enduml
    PUML
  end
  let(:node_source) do
    File.read(File.expand_path("../../fixtures/plantuml_usecase_component/" \
                               "plantuml-lrg-8-4-4.puml", __dir__))
  end

  def svg_of(source)
    REXML::Document.new(Sirena.render(source, notation: :plantuml))
  end

  # A two-colour link is drawn twice along one path, which counts once.
  def lines_of(svg)
    REXML::XPath.match(svg, "//path[@fill='none']").map do |path|
      [described_class::RelationPathPoints.call(path.attributes["d"]),
       path.attributes["stroke-width"].to_f / 2]
    end.uniq
  end

  def boxes_of(svg)
    labels = REXML::XPath.match(svg, "//text").select do |node|
      node.text.to_s.start_with?("[") && node.attributes["font-size"].to_f < 13
    end
    labels.map { |node| box_of(node) }
  end

  def box_of(node)
    left, baseline, size = %w[x y font-size].map do |name|
      node.attributes[name].to_f
    end
    width = described_class::Drawing::Face.width(node.text, size: size)
    [left, baseline - size, left + width, baseline + (size / 4)]
  end

  def crossed(box, lines)
    lines.count do |points, half|
      padded = box.zip([-half, -half, half, half]).map(&:sum)
      points.each_cons(2).any? do |from, to|
        described_class::SegmentBox.crosses?(padded, from, to)
      end
    end
  end

  # Each label is allowed the one line it names, which it sits against.
  def most_crossed(source)
    svg = svg_of(source)
    lines = lines_of(svg)
    boxes_of(svg).map { |box| crossed(box, lines) }.max
  end

  it "keeps the labels of a class diagram off every line but their own" do
    expect(most_crossed(class_source)).to be <= 1
  end

  it "keeps the labels of a node diagram off every line but their own" do
    expect(most_crossed(node_source)).to be <= 1
  end

  it "measures the labels it checks" do
    expect(boxes_of(svg_of(class_source)).size).to eq(5)
  end
end
