# frozen_string_literal: true

require "nokogiri"
require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include_context "with an isolated notation registry"
  include DejaVuText

  before do
    Sirena::Notation.send(:entries).delete(:plantuml)
    Sirena::Notation.register(Sirena::Notation::PlantUML)
  end

  let(:case_ids) do
    prefix = "resources.vega.nonreg.group2679."
    [
      "group_header_legacy_flat--5bcc726e80b1",
      "group_header_nested--af2e98871d2d",
      "group_header_nested_overrides_flat--29dfa779f376",
    ].map { |suffix| "#{prefix}#{suffix}" }
  end
  let(:root) { File.expand_path("../../../../plantuml", __dir__) }
  let(:boxed_participant_dimensions) do
    source = <<~PLANTUML
      @startuml
      box "Team"
      participant A
      end box
      A -> A : hi
      @enduml
    PLANTUML
    document = Nokogiri::XML(
      Sirena.render(source, notation: :plantuml),
    ).remove_namespaces!
    rectangle = document.at_xpath(
      '//g[starts-with(@id,"participant-A-")]/rect',
    )
    %w[width height].map { |attribute| rectangle[attribute].to_f }
  end
  let(:parity_evidence) do
    recognizer = SpecSupport::LayoutParity::PlantumlSequenceRecognizer.new
    case_ids.to_h do |id|
      source = File.read(File.join(root, "sequence", "#{id}.puml"))
      reference = File.join(root, "references", "sequence", "#{id}.svg")
      result = SpecSupport::LayoutParity::CaseComparator.compare(
        case_id: "plantuml/sequence/#{id}", type: "plantuml_sequence",
        reference: reference, reference_svg: File.read(reference),
        sirena_svg: Sirena.render(source, notation: :plantuml),
        reproduce: __FILE__, recognizer: recognizer,
        spatial_kinds: [:participant]
      )
      row = SpecSupport::LayoutParity::CaseLedger.build([result]).first
      [id, [row.dig("summary", "hard_failure"),
            row.dig("geometry", "matched"),
            row.dig("summary", "metrics").values_at(
              "worst_e_c", "worst_e_w", "worst_e_h", "worst_e_a"
            )]]
    end
  end

  it "matches ordinary group-header participant geometry" do
    expect(parity_evidence.values).to eq([
                                           [false, 3,
                                            [0.010529, 0.070367, 0.0, 0.070367]],
                                           [false, 3,
                                            [0.010529, 0.070367, 0.0, 0.070367]],
                                           [false, 3,
                                            [0.013606, 0.070367, 0.0, 0.070367]],
                                         ])
  end

  it "uses intrinsic boxed-participant dimensions" do
    width = dejavu("A", size: 14) + 14.0

    expect(boxed_participant_dimensions).to eq([width, 30.4883])
  end
end
