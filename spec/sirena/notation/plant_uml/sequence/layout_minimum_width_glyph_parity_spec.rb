# frozen_string_literal: true

require "digest"
require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:case_ids) do
    %w[
      resources.vega.nonreg.group20505.min_width_center--0385427ea4be
      resources.vega.nonreg.group20505.min_width_default--24072f84b995
      resources.vega.nonreg.group20505.min_width_left--4f6a53784edf
      resources.vega.nonreg.group20505.min_width_right--4f323bdad314
      resources.vega.nonreg.group20505.min_width_skinparam--577feb6055fb
    ]
  end

  let(:ordinary) do
    "@startuml\nparticipant A\nactor X\nA -> X : hi\n@enduml\n"
  end
  let(:teoz) do
    <<~PLANTUML
      @startuml
      !pragma teoz true
      <style>
      sequenceDiagram { participant { MinimumWidth 100 } }
      </style>
      participant A
      actor X
      A -> X : hi
      @enduml
    PLANTUML
  end
  let(:expected_digests) do
    %w[
      aaabc60c59baf44614f7ce5bce1ac2a9f7b85fc861a262c3a2c672564553f0f4
      55db1383aedfb8fd7917bc0bdf1a1020d92e639565159881b6b039519c19504c
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

  def parity_row(id)
    recognizer = SpecSupport::LayoutParity::PlantumlSequenceRecognizer.new
    result = SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: "plantuml/sequence/#{id}", type: "plantuml_sequence",
      reference: "spec/plantuml/references/sequence/#{id}.svg",
      reference_svg: reference(id),
      sirena_svg: Sirena.render(source(id), notation: :plantuml),
      reproduce: __FILE__, recognizer: recognizer,
      spatial_kinds: [:participant]
    )
    SpecSupport::LayoutParity::CaseLedger.build([result]).first
  end

  def digest(document)
    Digest::SHA256.hexdigest(Sirena.render(document, notation: :plantuml))
  end

  def parity_evidence(id)
    row = parity_row(id)
    [row.dig("summary", "hard_failure"), row.dig("geometry", "matched"),
     row.dig("summary", "metrics").values_at(
       "worst_e_c", "worst_e_w", "worst_e_h", "worst_e_a"
     )]
  end

  it "matches all five minimum-width mixed-glyph cases" do
    evidence = case_ids.map { |id| parity_evidence(id) }

    expect(evidence).to all(eq([false, 5,
                                [0.002187, 0.01386, 0.0, 0.01386]]))
  end

  it "preserves ordinary and teoz output bytes" do
    expect([digest(ordinary), digest(teoz)]).to eq(expected_digests)
  end
end
