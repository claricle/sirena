# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:case_ids) do
    %w[
      java.nonreg.simple.SequenceArrows_0001_Test--d918f796209f
      java.nonreg.simple.SequenceArrows_0002_Test--ae1299794d0b
    ]
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

  def recognizer
    SpecSupport::LayoutParity::PlantumlSequenceRecognizer.new
  end

  def result(id)
    SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: "plantuml/sequence/#{id}", type: "plantuml_sequence",
      reference: "spec/plantuml/references/sequence/#{id}.svg",
      reference_svg: reference(id),
      sirena_svg: Sirena.render(source(id), notation: :plantuml),
      reproduce: __FILE__, recognizer: recognizer,
      spatial_kinds: [:participant]
    )
  end

  def message_label(label)
    source = "@startuml\nA -> B : #{label}\n@enduml"
    Sirena::Notation::PlantUML::Sequence::Parser.new.parse(source)
      .messages.first.label
  end

  def reference_kind_counts(id)
    figure = SpecSupport::LayoutParity::SvgFigureExtractor
      .new(recognizer).extract(reference(id))
    figure.elements.map(&:kind).tally
  end

  def presence_evidence(id)
    row = SpecSupport::LayoutParity::CaseLedger.build([result(id)]).first
    [row.dig("summary", "hard_failure"), row.dig("geometry", "matched")]
  end

  it "reads PlantUML's doubled-quote message labels without their delimiters" do
    expect([
             message_label('""  -\\\\ \\"quoted\\"  ""'),
             message_label('  unquoted \\"content\\"  '),
           ]).to eq(['-\\ \\"quoted\\"', 'unquoted \\"content\\"'])
  end

  it "recognizes four participants and 124 arrows in each pinned reference" do
    counts = case_ids.map { |id| reference_kind_counts(id) }

    expect(counts).to eq(Array.new(2) { { participant: 4, message: 124 } })
  end

  it "matches every participant and arrow by semantic presence" do
    evidence = case_ids.map { |id| presence_evidence(id) }

    expect(evidence).to eq([[false, 128], [false, 128]])
  end
end
