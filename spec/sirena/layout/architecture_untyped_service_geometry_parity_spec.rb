# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Architecture do
  let(:layout) { described_class.new }
  let(:renderer) { Sirena::Renderer::Architecture.new }

  it "uses Mermaid's notched fallback without changing icon service bounds" do
    fallback = service_node("architecture-beta\n  service db\n")
    icon = service_node(
      "architecture-beta\n  service db(database)[Database]\n",
    )

    expect([fallback.icon, fallback.width, fallback.height])
      .to eq([nil, 90, 85])
    expect([icon.icon, icon.width, icon.height])
      .to eq(["database", 80, 80])
    expect(renderer.render(scene_for(fallback)).to_xml)
      .to include("<path", 'stroke-dasharray="8"')
    expect(renderer.render(scene_for(icon)).to_xml).to include("<rect")
  end

  it "matches both pinned no-icon services without structural loss" do
    simple, alongside_group = parity_results

    expect([simple.hard_failure?, simple.geometry.fetch(:matched),
            *geometry_metrics(simple)])
      .to match([false, 1, 0.0, 0.0, 0.0, 0.0])
    expect([alongside_group.hard_failure?,
            alongside_group.geometry.fetch(:matched),
            *geometry_metrics(alongside_group)])
      .to match([false, 2, be <= 0.01, be <= 1e-12,
                 be <= 1e-12, be <= 1e-12])
  end

  def service_node(source)
    diagram = Sirena::Notation::Mermaid.parse(source).diagram
    layout.call(diagram).children.find { |node| node.kind == "service" }
  end

  def scene_for(node)
    Sirena::Layout::Architecture::Scene.new(
      width: 200, height: 200, view_box: "0 0 200 200",
      children: [node], edges: []
    )
  end

  def parity_results
    %w[
      architecture/should_handle_a_simple_radar_definition-0a5b3a96.mmd
      architecture/xss_spec-3828c690.mmd
    ].map { |case_id| parity_result(case_id) }
  end

  def parity_result(case_id)
    reference = case_id.sub(".mmd", ".svg")
    policy = SpecSupport::LayoutParity::MeasurementPolicy.for(:architecture)
    SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: case_id, type: "architecture",
      reference: "spec/fixtures_mermaid/#{reference}",
      reference_svg: File.read("spec/fixtures_mermaid/#{reference}"),
      sirena_svg: Sirena.render(File.read("spec/mermaid/#{case_id}")),
      reproduce: __FILE__,
      recognizer: SpecSupport::LayoutParity::ArchitectureRecognizer.new,
      spatial_kinds: policy.spatial_kinds
    )
  end

  def geometry_metrics(result)
    result.geometry.values_at(:worst_e_c, :worst_e_w,
                              :worst_e_h, :worst_e_a)
  end
end
