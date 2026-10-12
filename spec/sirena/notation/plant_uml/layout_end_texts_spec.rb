# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Reads the rendered relation texts and class boxes of a PlantUML class
# diagram.
module PlantumlEndTextHelpers
  BOX_COORDINATES = %w[x y width height].freeze

  def render(body, engine: :smetana)
    pragma = engine == :smetana ? "!pragma layout smetana\n" : ""
    Sirena.render("@startuml\n#{pragma}#{body}\n@enduml\n",
                  notation: :plantuml)
  end

  def document(svg)
    REXML::Document.new(svg)
  end

  # Each relation's texts in drawing order, by group id.
  def relation_texts(svg)
    REXML::XPath.match(document(svg), "//g[starts-with(@id, 'relation-')]")
      .to_h do |group|
      [group.attributes["id"],
       REXML::XPath.match(group, "text").map { |text| text.text.to_s }]
    end
  end

  def text_at(svg, content)
    text = REXML::XPath.match(document(svg), "//text")
      .find { |node| node.text == content }
    [text.attributes["x"].to_f, text.attributes["y"].to_f,
     text.attributes["text-anchor"]]
  end

  def boxes(svg)
    REXML::XPath.match(document(svg), "//g[starts-with(@id, 'class-')]")
      .to_h do |group|
      rect = REXML::XPath.first(group, "rect")
      [group.attributes["id"].delete_prefix("class-"),
       BOX_COORDINATES.map { |name| rect.attributes[name].to_f }]
    end
  end

  def vertical_gap(svg, upper, lower)
    top = boxes(svg).fetch(upper)
    (boxes(svg).fetch(lower)[1] - (top[1] + top[3])).round(3)
  end

  def line_x(svg)
    path = REXML::XPath.first(document(svg), "//g/path").attributes["d"]
    path.scan(/-?\d+(?:\.\d+)?/).first.to_f
  end

  def text_sides(svg, contents)
    middle = line_x(svg)
    contents.to_h do |content|
      x, _, anchor = text_at(svg, content)
      [content, [x <=> middle, anchor]]
    end
  end

  def end_gaps(svg)
    _, tail, = text_at(svg, "t")
    _, head, = text_at(svg, "h")
    upper, lower = boxes(svg).values_at("A", "B")
    [(tail - (upper[1] + upper[3])).round(2),
     (lower[1] - head).round(2)]
  end

  def marker_dimensions(svg)
    points = marker_points(svg)
    horizontal, vertical = points.transpose
    [points.size, horizontal.max - horizontal.min,
     vertical.max - vertical.min]
  end

  def marker_points(svg)
    REXML::XPath.first(document(svg), "//polygon")
      .attributes["points"].split.map { |pair| pair.split(",").map(&:to_f) }
  end

  def hard_failure?(id)
    reference = "spec/plantuml/references/class/#{id}.svg"
    SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: id, type: "plantuml_class", reference: reference,
      reference_svg: File.read(reference),
      sirena_svg: Sirena.render(File.read("spec/plantuml/class/#{id}.puml"),
                                notation: :plantuml),
      reproduce: __FILE__,
      recognizer: SpecSupport::LayoutParity::PlantumlClassRecognizer.new,
      spatial_kinds: [:class]
    ).hard_failure?
  end
end

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include PlantumlEndTextHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:role_cases) do
    %w[
      resources.vega.nonreg.group2904.all_visibilities--00480b0ff655
      resources.vega.nonreg.group2904.diamond_at_tail--bb82b36b91be
      resources.vega.nonreg.group2904.icon_size_zero--5d137d5deadd
      resources.vega.nonreg.group2904.left_to_right--4e7a191e1721
      resources.vega.nonreg.group2904.role_without_visibility--6318bda823a1
    ]
  end

  let(:ends) { 'A "t"/"rt" --> "h"/"rh" B' }

  it "matches every pinned role-and-multiplicity relation" do
    expect(role_cases.to_h { |id| [id, hard_failure?(id)] })
      .to eq(role_cases.to_h { |id| [id, false] })
  end

  # Drawing orders read off the local PlantUML 1.2026.6.
  {
    [:smetana, "-->"] => %w[lab h t rt rh],
    [:smetana, "-up->"] => %w[lab t h rh rt],
    [:smetana, "-left->"] => %w[lab t h rh rt],
    [:smetana, "-right->"] => %w[lab h t rt rh],
    [:dot, "-->"] => %w[lab t rt h rh],
    [:dot, "-up->"] => %w[lab h rh t rt],
  }.each do |(engine, glyph), order|
    it "draws #{engine} `#{glyph}` end texts one by one in PlantUML's order" do
      svg = render(%(class A\nclass B\nA "t"/"rt" #{glyph} "h"/"rh" B : lab),
                   engine: engine)

      expect(relation_texts(svg).values).to eq([order])
    end
  end

  it "draws a lone role where its multiplicity would be" do
    svg = render(%(class A\nclass B\nA /"-r" --> B))

    expect(relation_texts(svg).values).to eq([["-r"]])
  end

  {
    "#prot" => ["1.", "prot"],
    "##z" => ["1.", "z"],
    "# m2" => ["1.", "m2"],
    "x#y" => ["x#y"],
  }.each do |content, pieces|
    it "draws the end text #{content.inspect} as #{pieces.inspect}" do
      svg = render(%(class A\nclass B\nA /"#{content}" --> B))

      expect(relation_texts(svg).values).to eq([pieces])
    end
  end

  it "sets a numbered item's text one space after its number" do
    svg = render(%(class A\nclass B\nA /"#prot" --> B))
    number, = text_at(svg, "1.")
    text, = text_at(svg, "prot")
    space = Sirena::TextMeasurement.measure("1. ", font_size: 12.6)[:width]

    expect(text - number).to be_within(1e-9).of(space)
  end

  it "puts a down line's multiplicities on its left and roles on its right" do
    svg = render("class A\nclass B\n#{ends}")

    expect(text_sides(svg, %w[t h rt rh]))
      .to eq("t" => [-1, "end"], "h" => [-1, "end"],
             "rt" => [1, "start"], "rh" => [1, "start"])
  end

  it "hugs each end text against its own end of a short line" do
    svg = render("class A\nclass B\n#{ends}")

    # Baselines just inside each class edge: under A, over B.
    expect(end_gaps(svg)).to eq([13.6, 4.15])
  end

  it "draws an aggregation diamond twelve long and eight wide" do
    svg = render("class A\nclass B\nA o-- B")

    expect(marker_dimensions(svg)).to eq([4, 8.0, 12.0])
  end

  # Gaps read off the local PlantUML 1.2026.6, as Graphviz ranks a
  # relation one rank per dash past the first.
  {
    [:smetana, "--"] => 36.0, [:smetana, "---"] => 73.0,
    [:smetana, "--------"] => 258.0, [:dot, "--"] => 60.0,
    [:dot, "---"] => 121.0, [:dot, "--------"] => 426.0
  }.each do |(engine, body), gap|
    it "ranks #{engine} `#{body}` classes #{gap} apart" do
      svg = render("class A\nclass B\nA #{body} B", engine: engine)

      expect(vertical_gap(svg, "A", "B")).to eq(gap)
    end
  end

  it "ranks across the page under left to right direction" do
    svg = render("left to right direction\nclass A\nclass B\nA --- B")
    a, b = boxes(svg).values_at("A", "B")

    expect([b[1], b[0] - (a[0] + a[2])]).to eq([a[1], 73.0])
  end

  # A label halves the ranks and takes a node in the middle of its relation.
  {
    smetana: [55.0, 37.0], dot: [77.0, 61.0]
  }.each do |engine, gaps|
    it "makes room for a #{engine} label and halves every other rank" do
      svg = render("class A\nclass B\nclass C\nA -- B : x\nB -- C",
                   engine: engine)

      expect([vertical_gap(svg, "A", "B"), vertical_gap(svg, "B", "C")])
        .to eq(gaps)
    end
  end

  it "sets a steep line's label beside it" do
    svg = render("class A\nclass B\nA -- B : uses")
    x, _, anchor = text_at(svg, "uses")

    expect([x - line_x(svg), anchor]).to eq([2.0, "start"])
  end

  it "ranks separate chains together, side by side a node gap apart" do
    svg = render("class A\nclass B\nclass C\nclass D\nA --> B\nC --> D")
    a, b, c, d = boxes(svg).values_at("A", "B", "C", "D")

    expect([c[1], d[1], b[0], c[0] - (a[0] + a[2])])
      .to eq([a[1], b[1], a[0], 18.0])
  end
end
