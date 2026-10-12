# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe SpecSupport::LayoutParity::PlantumlClassRecognizer do
  subject(:recognizer) { described_class.new }

  include SpecSupport::LayoutParity::FigureHelpers

  include_context "with an isolated notation registry"

  let(:spike_root) { File.expand_path("../../plantuml_spike", __dir__) }

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def source(name)
    File.read(File.join(spike_root, "cases", "#{name}.puml"))
  end

  def reference(name)
    File.read(File.join(spike_root, "references", "#{name}.svg"))
  end

  def keys(svg)
    extract(svg, recognizer).keys.sort_by(&:inspect)
  end

  def content_keys(svg)
    keys(svg).select { |key| key.first == :class_content }
  end

  def structural_keys(svg)
    keys(svg).reject { |key| key.first == :class_content }
  end

  def suffix_spaced(keys)
    keys.map do |key|
      key[0..1] + [key.last.map { |row| row.sub(/ : ([^:]*)\z/, ": \\1") }]
    end
  end

  def unresolved_svg
    <<~SVG
      <svg viewBox="0 0 100 100">
        <g id="class-A"><rect width="10" height="10"/></g>
        <g id="relation-0"><path d="M 50 50 L 60 60"/></g>
      </svg>
    SVG
  end

  it "keeps relation ownership aligned across producer member spacing" do
    name = "16-full-example"
    render = Sirena.render(source(name), notation: :plantuml)

    expect(structural_keys(render)).to eq(structural_keys(reference(name)))
    expect(content_keys(render)).to eq(suffix_spaced(content_keys(reference(name))))
  end

  it "resolves mixed arrow-side endpoints without reversing their owners" do
    name = "17-mixed-arrow-sides"
    render = Sirena.render(source(name), notation: :plantuml)
    expect(keys(render)).to eq(keys(reference(name)))
  end

  it "keeps an unresolved relation visible to presence comparison" do
    relation = extract(unresolved_svg, recognizer).elements.last
    expect(relation.key).to include("unresolved-endpoint")
  end
end
