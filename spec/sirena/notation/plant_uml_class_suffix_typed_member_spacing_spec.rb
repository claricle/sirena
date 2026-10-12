# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def parity_result(id)
    source = File.join("spec/plantuml/class", "#{id}.puml")
    reference = File.join("spec/plantuml/references/class", "#{id}.svg")
    SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: id, type: "plantuml_class", reference: reference,
      reference_svg: File.read(reference),
      sirena_svg: Sirena.render(File.read(source), notation: :plantuml),
      reproduce: __FILE__,
      recognizer: SpecSupport::LayoutParity::PlantumlClassRecognizer.new,
      spatial_kinds: [:class]
    )
  end

  def missing_content_keys(id)
    parity_result(id).invariants.filter_map do |failure|
      key = failure.fetch(:subject_keys)
      key.last if key.first == :class_content &&
        failure.dig(:normalized, :difference) == :missing
    end
  end

  it "matches pinned suffix-typed member text without a pre-colon space" do
    expected = {
      "resources.vega.migration.HideShow004_Test--16625d433c68" => [
        ["B", "B", "~run(): boolean"],
      ],
      "resources.vega.nonreg.group2903.reported_case--fd42e1abb616" => [
        ["Respuesta", "Respuesta", "fecha: Date"],
        ["Opcion", "Opcion", "texto: String"],
        ["Voto", "Voto", "getOpcion(): Opcion"],
      ],
    }

    missing = expected.to_h do |id, target_keys|
      [id, missing_content_keys(id) & target_keys]
    end
    expect(missing).to eq(expected.transform_values { [] })
  end
end
