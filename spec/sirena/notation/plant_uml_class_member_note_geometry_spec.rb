# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  def member_note_cases
    {
      "field_and_method_note--dad15be25c38" => %w[lightblue lightblue],
      "reported_case--cab9ac83dbb5" => %w[lightblue lightblue],
      "reversed_order--0dac1bb4078f" => %w[yellow yellow],
      "stereotype_colors--2b02c27ca536" => %w[lightblue lightblue],
      "three_members--15d11a71125a" => %w[blue blue blue],
    }
  end

  def source_path(name)
    Dir["spec/plantuml/class/*group2814.#{name}.puml"].fetch(0)
  end

  def source(name)
    File.read(source_path(name))
  end

  def parity_result(name)
    reference = source_path(name).sub("/class/", "/references/class/")
      .sub(/\.puml\z/, ".svg")
    SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: name, type: "plantuml_class", reference: reference,
      reference_svg: File.read(reference),
      sirena_svg: Sirena.render(source(name), notation: :plantuml),
      reproduce: __FILE__,
      recognizer: SpecSupport::LayoutParity::PlantumlClassRecognizer.new,
      spatial_kinds: [:class],
    )
  end

  def note_fills(name)
    document = REXML::Document.new(
      Sirena.render(source(name), notation: :plantuml),
    )
    REXML::XPath.match(document, "//g[starts-with(@id, 'note-')]/*[1]")
      .map { |shape| shape.attributes["fill"] }
  end

  def callout_boxes(name)
    reference = Nokogiri::XML(
      File.read(source_path(name).sub("/class/", "/references/class/")
        .sub(/\.puml\z/, ".svg")),
    )
    rendered = Nokogiri::XML(
      Sirena.render(source(name), notation: :plantuml),
    )
    reference.remove_namespaces!
    rendered.remove_namespaces!
    reference_paths = reference.xpath("//path[contains(@d, 'A0,0')]")
    rendered_paths = rendered.xpath(
      "//g[starts-with(@id, 'note-')]/path",
    )
    [reference_paths, rendered_paths].map do |paths|
      paths.map do |path|
        points = SpecSupport::LayoutParity::PathPoints.new(path["d"]).points
        SpecSupport::LayoutParity::Bbox.from_points(points)
      end
    end
  end

  def callout_errors(name)
    reference, rendered = callout_boxes(name)
    reference.zip(rendered).flat_map do |expected, actual|
      [((actual.width / expected.width) - 1).abs,
       ((actual.height / expected.height) - 1).abs]
    end
  end

  it "preserves prefix and suffix member type order through the IR" do
    input = "@startuml\nclass C {\nint before\nafter : int\n}\n@enduml\n"
    graph = Sirena::Notation::PlantUML.parse(input).diagram
    scene = described_class.new.call(graph)
    rows = scene.boxes.first.texts.map(&:content)

    expect(rows).to eq(["C", "int before", "after : int"])
  end

  it "matches the pinned class geometry without presence failures" do
    evidence = member_note_cases.keys.map do |name|
      result = parity_result(name)
      metrics = result.geometry.values_at(
        :worst_e_c, :worst_e_w, :worst_e_h, :worst_e_a
      )
      [result.hard_failure?, metrics.all? { |metric| metric <= 0.15 }]
    end

    expected = Array.new(member_note_cases.length) { [false, true] }
    expect(evidence).to eq(expected)
  end

  it "uses each pinned member-note stack's shared fill" do
    evidence = member_note_cases.to_h do |name, fills|
      [name, note_fills(name)]
    end

    expect(evidence).to eq(member_note_cases)
  end

  it "matches the pinned member-note callout dimensions" do
    errors = member_note_cases.keys.flat_map { |name| callout_errors(name) }

    expect(errors).to all(be <= 0.15)
  end
end
