# frozen_string_literal: true

require "digest"
require "nokogiri"
require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include_context "with an isolated notation registry"

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  let(:case_ids) do
    %w[
      java.nonreg.simple.SequenceArrows_0001_Test--d918f796209f
      java.nonreg.simple.SequenceArrows_0002_Test--ae1299794d0b
    ]
  end

  let(:teoz_source) { "@startuml\n!pragma teoz true\nA -> B\n@enduml" }
  let(:noted_source) do
    <<~PLANTUML
      @startuml
      A -> B : hi
      note right : a note
      @enduml
    PLANTUML
  end

  def root
    File.expand_path("../../../../plantuml", __dir__)
  end

  def source(id)
    File.read(File.join(root, "sequence", "#{id}.puml"))
  end

  def reference(id)
    File.read(File.join(root, "references", "sequence", "#{id}.svg"))
  end

  def rendered(id)
    Sirena.render(source(id), notation: :plantuml)
  end

  def figure(svg)
    recognizer = SpecSupport::LayoutParity::PlantumlSequenceRecognizer.new
    SpecSupport::LayoutParity::SvgFigureExtractor.new(recognizer).extract(svg)
  end

  def participants(svg)
    figure(svg).elements.select { |element| element.kind == :participant }
      .to_h { |element| [element.label, element.bbox] }
  end

  def message_baselines(svg, reference:)
    document = Nokogiri::XML(svg).tap(&:remove_namespaces!)
    path = if reference
             '/svg/g/text[@font-size="13"]'
           else
             '//g[starts-with(@id,"message-")]/text'
           end
    document.xpath(path).map { |text| text["y"].to_f }
  end

  def parity_row(id)
    recognizer = SpecSupport::LayoutParity::PlantumlSequenceRecognizer.new
    result = SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: "plantuml/sequence/#{id}", type: "plantuml_sequence",
      reference: "spec/plantuml/references/sequence/#{id}.svg",
      reference_svg: reference(id), sirena_svg: rendered(id),
      reproduce: __FILE__, recognizer: recognizer,
      spatial_kinds: [:participant]
    )
    SpecSupport::LayoutParity::CaseLedger.build([result]).first
  end

  def teoz_round_trip(source)
    diagram = Sirena::Notation::PlantUML::Sequence::Parser.new.parse(source)
    graph = Sirena::Notation::PlantUML::Sequence::IRAdapter.call(diagram)
    [graph.nodes.any? { |node| node.role == "teoz" },
     Sirena::Notation::PlantUML::Sequence::IRReader.call(graph).teoz?]
  end

  def digest(document)
    Digest::SHA256.hexdigest(Sirena.render(document, notation: :plantuml))
  end

  def head_errors(id)
    expected = participants(reference(id))
    actual = participants(rendered(id))
    expected.keys.flat_map do |label|
      head_error(expected.fetch(label), actual.fetch(label))
    end
  end

  def head_error(reference_box, sirena_box)
    [(sirena_box.width - reference_box.width).abs / reference_box.width,
     (sirena_box.height - reference_box.height).abs / reference_box.height]
  end

  def baseline_evidence(id)
    expected = message_baselines(reference(id), reference: true)
    actual = message_baselines(rendered(id), reference: false)
    [expected.size, actual.size,
     expected.zip(actual).map { |left, right| (left - right).abs }.max]
  end

  def center_parity_evidence(id)
    row = parity_row(id)
    [row.dig("summary", "hard_failure"),
     row.dig("geometry", "matched"),
     row.dig("summary", "metrics", "worst_e_c")]
  end

  it "carries teoz through typed IR without selecting it for ordinary input" do
    round_trips = [teoz_source, "@startuml\nA -> B\n@enduml"].map do |text|
      teoz_round_trip(text)
    end

    expect(round_trips).to eq([[true, true], [false, false]])
  end

  it "preserves the established non-teoz SVG bytes" do
    expect(digest(noted_source))
      .to eq("26704b2d8430aef533b123ddd820b4086288ecd9d89e6fdef123d3e21960155a")
  end

  it "matches the pinned teoz participant-head dimensions" do
    errors = case_ids.flat_map { |id| head_errors(id) }

    expect(errors.max).to be < 0.08
  end

  it "matches all 124 pinned message baselines in each case" do
    evidence = case_ids.map { |id| baseline_evidence(id) }

    expect(evidence).to all(satisfy do |expected, actual, worst|
      expected == 124 && actual == 124 && worst < 0.002
    end)
  end

  it "removes the measured center-parity misses without losing elements" do
    evidence = case_ids.map { |id| center_parity_evidence(id) }

    expect(evidence).to all(satisfy do |hard_failure, matched, center_error|
      !hard_failure && matched == 128 && center_error < 0.01
    end)
  end
end
