# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ErDiagram do
  let(:case_id) { "unknown/yari2-dc83acff.mmd" }
  let(:source) { File.read("spec/mermaid/#{case_id}") }
  let(:reference) do
    File.read("spec/fixtures_mermaid/er_diagram/yari2-dc83acff.svg")
  end

  let(:result) { parity_result }
  let(:metrics) do
    result.geometry.values_at(:worst_e_c, :worst_e_w, :worst_e_h, :worst_e_a)
  end

  it "carries config.layout through the Mermaid parse result" do
    expect(Sirena::Notation::Mermaid.parse(source).layout_engine).to eq(:elk)
  end

  it "keeps an explicit caller engine ahead of source configuration" do
    body = Sirena::Source.split(source).fetch(:body)

    expect(Sirena.render(source, layout_engine: :grid))
      .to eq(Sirena.render(body))
  end

  it "keeps config-free default ER output byte-identical" do
    ordinary = "erDiagram\n  CUSTOMER ||--o{ ORDER : places\n"

    expect(Sirena.render(ordinary))
      .to eq(Sirena.render(ordinary, layout_engine: :grid))
  end

  it "meets the pinned ER geometry thresholds without structural loss" do
    expect([result.hard_failure?, result.geometry.fetch(:matched), *metrics])
      .to match([false, 15, be <= 0.08, be <= 0.15,
                 be <= 0.15, be <= 0.15])
  end

  def parity_result
    SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: case_id,
      type: "er_diagram",
      reference: "spec/fixtures_mermaid/er_diagram/yari2-dc83acff.svg",
      reference_svg: reference,
      sirena_svg: Sirena.render(source),
      reproduce: __FILE__,
      recognizer: SpecSupport::LayoutParity::ErDiagramRecognizer.new,
      spatial_kinds: [:entity],
    )
  end
end
