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
      title Bracketed line style mix
      class foo
      class bar
      bar1 : [#red,thickness=1]
      bar2 : [#red,dashed,thickness=2]
      bar3 : [#green,dashed,thickness=4]
      bar4 : [#blue,dotted,thickness=8]
      bar5 : [#blue,plain,thickness=16]

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
    size = number(node, "font-size")
    width = described_class::Drawing::Face.width(node.text, size: size)
    left = number(node, "x") - back(node.attributes["text-anchor"], width)
    top = number(node, "y") - size
    [left, top, left + width, top + (size * 1.25)]
  end

  def number(node, name)
    node.attributes[name].to_f
  end

  # How far left of its anchor the text starts.
  def back(anchor, width)
    { "middle" => width / 2, "end" => width }.fetch(anchor, 0.0)
  end

  def crossed(box, lines)
    lines.count do |points, half|
      padded = box.zip([-half, -half, half, half]).map(&:sum)
      points.each_cons(2).any? do |from, to|
        described_class::SegmentBox.crosses?(padded, from, to)
      end
    end
  end

  # How many lines run through each label, in drawing order. A label may
  # lie against the one line it names, so one is allowed.
  def crossings_of(source)
    svg = svg_of(source)
    lines = lines_of(svg)
    boxes_of(svg).map { |box| crossed(box, lines) }
  end

  it "keeps the labels of a class diagram off every line but their own" do
    expect(crossings_of(class_source)).to eq([0, 0, 1, 0, 0])
  end

  # Two labels of this diagram still lie across another's line, where the
  # lines leave no clear spot near their own.
  it "leaves two labels of a node diagram across another line" do
    expect(crossings_of(node_source)).to eq([1, 0, 1, 1, 0, 0])
  end

  it "measures the labels it checks" do
    expect(boxes_of(svg_of(class_source)).size).to eq(5)
  end
end
