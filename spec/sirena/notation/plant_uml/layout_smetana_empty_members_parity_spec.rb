# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  let(:root) { File.expand_path("../../../plantuml", __dir__) }

  let(:case_ids) do
    %w[
      resources.vega.nonreg.group2712.down_direction--b7562ecaf08a
      resources.vega.nonreg.group2712.left_direction--817e051688df
      resources.vega.nonreg.group2712.reported_case--4d4d68cc75f8
      resources.vega.nonreg.group2712.right_direction--4bc244e3377d
    ]
  end

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  it "matches every pinned Smetana empty-member class family" do
    checks = case_ids.map { |id| parity_checks(id) }

    expect(checks).to all(eq([true, true, true, true, true]))
  end

  def parity_checks(id)
    result = comparison(id)
    metrics = result.geometry
    [!result.hard_failure?,
     metrics.fetch(:worst_e_c) <= 0.08,
     metrics.fetch(:worst_e_w) <= 0.15,
     metrics.fetch(:worst_e_h) <= 0.15,
     metrics.fetch(:worst_e_a) <= 0.15]
  end

  def comparison(id)
    source = File.read(File.join(root, "class", "#{id}.puml"))
    reference = File.join(root, "references", "class", "#{id}.svg")
    SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: "plantuml/class/#{id}", type: "plantuml_class",
      reference: reference, reference_svg: File.read(reference),
      sirena_svg: Sirena.render(source, notation: :plantuml),
      reproduce: __FILE__,
      recognizer: SpecSupport::LayoutParity::PlantumlClassRecognizer.new,
      spatial_kinds: [:class]
    )
  end
end
