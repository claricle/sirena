# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe SpecSupport::LayoutParity::PlantumlClassRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:recognizer) { described_class.new }
  let(:case_id) do
    "resources.vega.svg.interactive.SVG0004_Svek--d500aa856a7e"
  end

  it "matches PlantUML's escaped interactive identity to the source name" do
    reference_keys = keys(interactive_svg(:reference))

    expect(keys(interactive_svg(:sirena))).to eq(reference_keys)
  end

  it "matches every semantic element in the pinned interactive case" do
    expect(pinned_result.hard_failure?).to be(false)
  end

  def keys(svg)
    extract(svg, recognizer).keys.sort_by(&:inspect)
  end

  def interactive_svg(producer)
    identity = interactive_identity(producer)
    indent = producer == :sirena ? "\u00A0" * 4 : ""
    <<~SVG
      <svg viewBox="0 0 100 100">
        <g #{identity}><rect width="50" height="50"/>
          <text>Class</text><text>\u00A0</text><text>#{indent}!</text>
        </g>
      </svg>
    SVG
  end

  def interactive_identity(producer)
    if producer == :reference
      return 'class="entity" data-qualified-name="pkg.Class.r.n.t."'
    end

    'id="class-pkg.Class\\r\\n\\t¡"'
  end

  def pinned_result
    reference = "spec/plantuml/references/class/#{case_id}.svg"
    SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: case_id, type: "plantuml_class", reference: reference,
      reference_svg: File.read(reference), sirena_svg: rendered_case,
      reproduce: __FILE__, recognizer: recognizer, spatial_kinds: [:class]
    )
  end

  def rendered_case
    source = File.read("spec/plantuml/class/#{case_id}.puml")
    Sirena.render(source, notation: :plantuml)
  end
end
