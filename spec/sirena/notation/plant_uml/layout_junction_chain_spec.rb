# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Reads the rendered geometry of a PlantUML class diagram.
module PlantumlJunctionChainHelpers
  BOX_ATTRIBUTES = %w[x y width height].freeze

  def render(body)
    Sirena.render("@startuml\n!pragma layout smetana\n#{body}\n@enduml\n",
                  notation: :plantuml)
  end

  def boxes(svg)
    REXML::XPath.match(REXML::Document.new(svg), "//g[@id]").to_h do |group|
      rect = REXML::XPath.first(group, "rect")
      next [group.attributes["id"], nil] unless rect

      [group.attributes["id"],
       BOX_ATTRIBUTES.map { |name| rect.attributes[name].to_f }]
    end.compact
  end

  # The two ends of each relation line, by group id.
  def lines(svg)
    REXML::XPath.match(REXML::Document.new(svg), "//g[@id]").filter_map do |g|
      path = REXML::XPath.first(g, "path")
      next unless path && g.attributes["id"].match?(/\A(relation|junction)-/)

      numbers = path.attributes["d"].scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
      [g.attributes["id"], [numbers.first(2), numbers.last(2)]]
    end.to_h
  end

  def marker_owners(svg)
    REXML::XPath.match(REXML::Document.new(svg), "//g[polygon]")
      .map { |group| group.attributes["id"] }
  end

  def parity_failures(id)
    reference = "spec/plantuml/references/class/#{id}.svg"
    SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: id, type: "plantuml_class", reference: reference,
      reference_svg: File.read(reference),
      sirena_svg: Sirena.render(File.read("spec/plantuml/class/#{id}.puml"),
                                notation: :plantuml),
      reproduce: __FILE__,
      recognizer: SpecSupport::LayoutParity::PlantumlClassRecognizer.new,
      spatial_kinds: [:class]
    ).invariants
  end
end

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include PlantumlJunctionChainHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:junction_cases) do
    %w[
      resources.vega.nonreg.group2712.down_direction--b7562ecaf08a
      resources.vega.nonreg.group2712.left_direction--817e051688df
      resources.vega.nonreg.group2712.reported_case--4d4d68cc75f8
      resources.vega.nonreg.group2712.right_direction--4bc244e3377d
      resources.vega.nonreg.group2903.left_to_right--8310bfc61aae
      resources.vega.nonreg.group2903.nodesep_ranksep--7c073f601760
      resources.vega.nonreg.group2903.reported_case--fd42e1abb616
      resources.vega.nonreg.group2903.two_association_classes--5589df921b7b
    ]
  end

  it "draws every pinned association class as PlantUML's junction legs" do
    failures = junction_cases.to_h { |id| [id, parity_failures(id)] }

    expect(failures).to eq(junction_cases.to_h { |id| [id, []] })
  end

  describe "a relation carrying an association class" do
    let(:svg) { render("class A\nclass B\nclass C\nA -- B\n(A, B) .. C") }
    let(:box) { boxes(svg) }
    let(:line) { lines(svg) }

    it "stacks the classes one rank apart around a junction node" do
      a, b, c = box.values_at("class-A", "class-B", "class-C")
      junction_top = line["relation-0-from"].last[1]
      junction_bottom = line["relation-0-to"].first[1]

      expect([a[0], b[0], c[1] + (c[3] / 2)])
        .to eq([b[0], a[0], (junction_top + junction_bottom) / 2])
    end

    it "splits the relation into two straight legs on one line" do
      xs = %w[relation-0-from relation-0-to].flat_map do |id|
        line[id].map(&:first)
      end

      expect(xs.uniq.size).to eq(1)
    end

    it "links the junction node to the association class side on" do
      start, finish = line["junction-0"]
      c = box["class-C"]

      expect([start[1], finish]).to eq([finish[1], [c[0], c[1] + (c[3] / 2)]])
    end
  end

  it "lays a left-worded relation across one rank in written order" do
    svg = render("class A\nclass B\nclass C\nA -left-> B\n(A, B) . C")
    a, b, c = boxes(svg).values_at("class-A", "class-B", "class-C")
    junction = (lines(svg)["relation-0-from"].last[0] +
                lines(svg)["relation-0-to"].first[0]) / 2

    # Two node gaps of 18 either side of the 16-wide junction node.
    expect([b[1], b[0] - (a[0] + a[2]), c[0] + (c[2] / 2)])
      .to eq([a[1], 52.0, junction])
  end

  it "draws an up-worded arrowhead on the leg leaving the first class" do
    svg = render("class A\nclass B\nclass C\nA -up-> B\n(A, B) . C")

    expect(marker_owners(svg)).to eq(["relation-0-from"])
  end

  it "keeps a down-worded arrowhead on the leg reaching the second class" do
    svg = render("class A\nclass B\nclass C\nA -down-> B\n(A, B) . C")

    expect(marker_owners(svg)).to eq(["relation-0-to"])
  end

  it "places a one-character relation one node gap beside its first class" do
    a, b = boxes(render("class A\nclass B\nA .> B"))
      .values_at("class-A", "class-B")

    expect([b[1], b[0] - (a[0] + a[2])]).to eq([a[1], 18.0])
  end

  it "draws PlantUML's notched arrowhead, nine long and eight wide" do
    svg = render("class A\nclass B\nA --> B")
    points = REXML::XPath.first(REXML::Document.new(svg), "//polygon")
      .attributes["points"].split.map { |pair| pair.split(",").map(&:to_f) }
    xs, ys = points.transpose

    expect([points.size, xs.max - xs.min, ys.max - ys.min])
      .to eq([4, 8.0, 9.0])
  end

  it "meets the legs at the relation's middle when the grid places them" do
    svg = render("class A\nclass B\nclass C\nA -- B : uses\n(A, B) .. C")
    from, to = lines(svg).values_at("relation-0-from", "relation-0-to")

    expect(from.last).to eq(to.first)
  end
end
