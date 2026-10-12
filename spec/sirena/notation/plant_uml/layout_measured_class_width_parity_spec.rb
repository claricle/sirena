# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  subject(:checks) do
    protected_cases.map do |id, (previous_center, previous_width)|
      source = File.read(File.join(root, "class", "#{id}.puml"))
      reference = File.join(root, "references", "class", "#{id}.svg")
      metrics = SpecSupport::LayoutParity::CaseComparator.compare(
        case_id: "plantuml/class/#{id}", type: "plantuml_class",
        reference: reference, reference_svg: File.read(reference),
        sirena_svg: Sirena.render(source, notation: :plantuml),
        reproduce: __FILE__,
        recognizer: SpecSupport::LayoutParity::PlantumlClassRecognizer.new,
        spatial_kinds: [:class]
      ).geometry
      [metrics.fetch(:worst_e_c) <= previous_center,
       metrics.fetch(:worst_e_w) < previous_width]
    end
  end

  include_context "with an isolated notation registry"

  let(:protected_cases) do
    {
      "resources.vega.nonreg.group2904.left_to_right--4e7a191e1721" =>
        [0.14470679997932506, 1.059430001261401],
      "resources.vega.nonreg.simple.QualifiedAssoc001--8c3b78057dc3" =>
        [0.8932121088794794, 2.954239562661105],
      "resources.vega.svg.interactive.SVG0006_Svek--70f5757ed2ca" =>
        [0.2834054761456912, 2.8406882513346394],
    }
  end

  let(:root) { File.expand_path("../../../plantuml", __dir__) }

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  it "shrinks class widths without moving protected relation topologies" do
    expect(checks).to all(eq([true, true]))
  end
end
