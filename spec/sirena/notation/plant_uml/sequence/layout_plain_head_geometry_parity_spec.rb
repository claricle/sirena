# frozen_string_literal: true

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
    prefix = "resources.vega.nonreg.group2679."
    [
      "group_header_legacy_flat--5bcc726e80b1",
      "group_header_nested--af2e98871d2d",
      "group_header_nested_overrides_flat--29dfa779f376",
    ].map { |suffix| "#{prefix}#{suffix}" }
  end
  let(:expected_metrics) do
    {
      case_ids[0] => [0.028282, 0.058283, 0.0, 0.058283],
      case_ids[1] => [0.028282, 0.058283, 0.0, 0.058283],
      case_ids[2] => [0.017647, 0.058283, 0.0, 0.058283],
    }
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
    expected = expected_metrics.transform_values do |metrics|
      [false, 3, metrics]
    end

    expect(parity_evidence).to eq(expected)
  end

  it "keeps the established boxed-participant dimensions" do
    expect(boxed_participant_dimensions).to eq([80.0, 36.0])
  end
end
