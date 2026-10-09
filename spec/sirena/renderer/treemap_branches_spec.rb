# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/treemap"

RSpec.describe Sirena::Renderer::Treemap do
  let(:renderer) { described_class.new }
  let(:base_cell) do
    {
      label: "Cell",
      value: 10,
      x: 0,
      y: 0,
      width: 100,
      height: 80,
      css_class: nil,
      depth: 0,
      children: [],
    }
  end

  def render_cell(cell, class_defs = {})
    renderer.render(
      width: 200,
      height: 120,
      title: nil,
      cells: [cell],
      class_defs: class_defs,
    ).to_xml
  end

  it "falls back to the depth fill when a class defines only stroke" do
    cell = base_cell.merge(css_class: "outlined", depth: 1)

    expect(render_cell(cell, "outlined" => "stroke:#123456"))
      .to include('fill="#ffffb3"')
  end

  it "falls back to the theme stroke when a class defines only fill" do
    cell = base_cell.merge(css_class: "filled")

    expect(render_cell(cell, "filled" => "fill:#abcdef"))
      .to include('stroke="#000000"')
  end

  it "uses depth colors for an unknown class" do
    cell = base_cell.merge(css_class: "missing", depth: 2)

    expect(render_cell(cell)).to include('fill="#bebada"')
  end

  it "uses depth colors when no class is assigned" do
    expect(render_cell(base_cell.merge(depth: 3))).to include('fill="#fb8072"')
  end

  it "renders a zero value for a leaf" do
    expect(render_cell(base_cell.merge(value: 0))).to match(%r{<text[^>]*>0</text>})
  end

  it "does not render a parent value" do
    child = base_cell.merge(label: "Child", value: nil, x: 10, y: 20)
    parent = base_cell.merge(label: "Parent", value: 99, children: [child])

    expect(render_cell(parent)).not_to match(%r{<text[^>]*>99</text>})
  end

  it "renders descendants recursively" do
    grandchild = base_cell.merge(label: "Grandchild", x: 20, y: 40)
    child = base_cell.merge(label: "Child", value: nil, x: 10, y: 20, children: [grandchild])
    parent = base_cell.merge(label: "Parent", value: nil, children: [child])

    expect(render_cell(parent)).to include("Grandchild")
  end

  it "keeps a label at the truncation boundary" do
    cell = base_cell.merge(label: "1234567890", width: 80)

    expect(render_cell(cell)).to include(">1234567890</text>")
  end

  it "truncates a label beyond the boundary" do
    cell = base_cell.merge(label: "12345678901", width: 80)

    expect(render_cell(cell)).to include(">1234567...</text>")
  end
end
