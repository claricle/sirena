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

  def root
    File.expand_path("../../plantuml", __dir__)
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

  it "matches all five minimum-width mixed-glyph cases" do
    evidence = case_ids.map do |id|
      row = parity_row(id)
      [row.dig("summary", "hard_failure"), row.dig("geometry", "matched"),
       row.dig("summary", "metrics").values_at(
         "worst_e_c", "worst_e_w", "worst_e_h", "worst_e_a"
       )]
    end

    expect(evidence).to all(eq([false, 5,
                                [0.002195, 0.013916, 0.0, 0.013916]]))
  end

  it "preserves ordinary and teoz output bytes" do
    ordinary = "@startuml\nparticipant A\nactor X\nA -> X : hi\n@enduml\n"
    teoz = <<~PLANTUML
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

    expect([digest(ordinary), digest(teoz)]).to eq([
                                                     "49c4f351162c17532b8b9b6378b6f40ec45fb400feb3d3febaee27ccaeb75530",
                                                     "55db1383aedfb8fd7917bc0bdf1a1020d92e639565159881b6b039519c19504c",
                                                   ])
  end
end
