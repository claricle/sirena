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

  def suffix_spaced_keys(svg)
    keys(svg).map do |key|
      next key unless key.first == :class_content

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

  def one_unresolved_end_svg
    <<~SVG
      <svg viewBox="0 0 100 100">
        <g class="entity" data-qualified-name="A" id="ent1">
          <rect width="10" height="10"/>
        </g>
        <g class="link" data-entity-1="ent1" data-entity-2="ent9" id="lnk2">
          <path d="M 5 10 L 5 40"/>
        </g>
      </svg>
    SVG
  end

  def stereotype_svg(producer)
    identity = if producer == :reference
                 'class="entity" data-qualified-name="Access"'
               else
                 'id="class-Access"'
               end
    stereotype = producer == :reference ? "«Entity»" : "&lt;&lt;Entity&gt;&gt;"
    <<~SVG
      <svg viewBox="0 0 100 100">
        <g #{identity}>
          <rect width="80" height="40"/>
          <text>#{stereotype}</text><text>Access</text>
        </g>
      </svg>
    SVG
  end

  def class_note_svg(producer)
    note = if producer == :reference
             <<~NOTE
               <g class="entity" data-qualified-name="GMN2">
                 <path d="M 20 0 L 80 0 L 80 20 L 20 20 Z"/>
                 <text>yellow class note</text>
               </g>
             NOTE
           else
             ""
           end
    identity = if producer == :reference
                 'class="entity" data-qualified-name="C"'
               else
                 'id="class-C"'
               end
    <<~SVG
      <svg viewBox="0 0 100 100">
        <g #{identity}><rect width="10" height="10"/><text>C</text></g>
        #{note}
      </svg>
    SVG
  end

  def translated_relation_svg(producer)
    if producer == :reference
      return <<~SVG
        <svg viewBox="0 0 100 200">
          <g class="entity" data-qualified-name="Sally" id="sally">
            <rect y="100" width="10" height="10"/><text>Sally</text>
          </g>
          <g class="entity" data-qualified-name="Bob" id="bob">
            <rect y="150" width="10" height="10"/><text>Bob</text>
          </g>
          <g class="link" data-entity-1="sally" data-entity-2="bob">
            <path d="M 5 110 L 5 150"/>
          </g>
        </svg>
      SVG
    end

    <<~SVG
      <svg viewBox="0 0 100 200">
        <g transform="translate(0 100)">
          <g id="class-Sally"><rect width="10" height="10"/><text>Sally</text></g>
          <g id="class-Bob"><rect y="50" width="10" height="10"/><text>Bob</text></g>
          <g id="relation-0"><path d="M 5 10 L 5 50"/></g>
        </g>
      </svg>
    SVG
  end

  def qualified_identity_svg(producer)
    if producer == :reference
      return <<~SVG
        <svg viewBox="0 0 100 100">
          <g class="entity" data-qualified-name="pkg.World" id="world">
            <rect width="20" height="20"/><text>World</text>
          </g>
          <g class="entity" data-qualified-name="dummy.2" id="dummy">
            <rect x="60" width="20" height="20"/><text>dummy$2</text>
          </g>
          <g class="link" data-entity-1="world" data-entity-2="dummy">
            <path d="M 20 10 L 60 10"/>
          </g>
        </svg>
      SVG
    end

    <<~SVG
      <svg viewBox="0 0 100 100">
        <g id="class-World"><rect width="20" height="20"/><text>World</text></g>
        <g id="class-dummy$2">
          <rect x="60" width="20" height="20"/><text>dummy$2</text>
        </g>
        <g id="relation-0"><path d="M 20 10 L 60 10"/></g>
      </svg>
    SVG
  end

  def duplicate_titles_svg
    <<~SVG
      <svg viewBox="0 0 100 100">
        <g class="entity" data-qualified-name="left.User">
          <rect width="20" height="20"/><text>User</text>
        </g>
        <g class="entity" data-qualified-name="right.User">
          <rect x="60" width="20" height="20"/><text>User</text>
        </g>
      </svg>
    SVG
  end

  it "keeps relation ownership aligned across producer member spacing" do
    name = "16-full-example"
    render = Sirena.render(source(name), notation: :plantuml)

    expect(keys(render)).to eq(suffix_spaced_keys(reference(name)))
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

  it "keys only the end of a link that reaches no class as unresolved" do
    relation = extract(one_unresolved_end_svg, recognizer).elements.last

    expect(relation.key).to eq(["A", "unresolved-endpoint", 0])
  end

  it "normalizes stereotype decorations from both producers" do
    expect(keys(stereotype_svg(:reference)))
      .to eq(keys(stereotype_svg(:sirena)))
  end

  it "does not classify PlantUML note groups as classes" do
    expect(keys(class_note_svg(:reference)))
      .to eq(keys(class_note_svg(:sirena)))
  end

  it "resolves relation endpoints after producer transforms" do
    expect(keys(translated_relation_svg(:reference)))
      .to eq(keys(translated_relation_svg(:sirena)))
  end

  it "matches package-qualified and dollar-sanitized producer identities" do
    expect(keys(qualified_identity_svg(:reference)))
      .to eq(keys(qualified_identity_svg(:sirena)))
  end

  it "retains qualified identities when visible titles are ambiguous" do
    class_keys = keys(duplicate_titles_svg).select { |key| key.first == :class }

    expect(class_keys.map(&:last)).to contain_exactly("left.User", "right.User")
  end
end
