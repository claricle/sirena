# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

# Requiring the notation registers it; restore the suite's baseline here and
# register inside the isolated context, as the class notation's spec does.
Sirena::Notation.send(:entries).delete(:plantuml)

module PlantUmlSequenceCorpus
  DIR = File.expand_path("../../../../plantuml/sequence", __dir__)

  # Every case of spec/plantuml/sequence the slice renders today. A case
  # joins this list when it renders; it never leaves it.
  GROUP = "resources.vega.nonreg.group2791."
  RENDERED = %w[
    box_between_external_participants--7d1d5500d228
    box_forward_self_message_clears_next_participant--1a24d5f462c1
    box_reverse_self_message_clears_previous_participant--c797d0cd3eab
    self_message_leftmost_of_multi--0742b0602928
    self_message_leftmost_participant--9efe4ddda292
    self_message_reverse_only--b0355d4c2434
    self_message_solo--9d48b2180ff0
  ].map { |tail| "#{GROUP}#{tail}" }.freeze

  def source_of(name)
    File.read(File.join(DIR, "#{name}.puml"))
  end

  def unread_cases
    Dir.glob(File.join(DIR, "*.puml")).map { |p| File.basename(p, ".puml") }
      .sort - RENDERED
  end

  def refusal(name)
    Sirena.render(source_of(name), notation: :plantuml)
    nil
  rescue Sirena::Notation::PlantUML::UnsupportedConstructError,
         Sirena::Parser::ParseError => e
    e
  end
end

RSpec.describe Sirena::Notation::PlantUML::Sequence do
  include PlantUmlSequenceCorpus

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  PlantUmlSequenceCorpus::RENDERED.each do |name|
    it "renders well-formed SVG for #{name.split('.').last}" do
      svg = Sirena.render(source_of(name), notation: :plantuml)

      expect(REXML::Document.new(svg).root.name).to eq("svg")
    end
  end

  it "draws one lifeline per declared participant in a rendered case" do
    name = PlantUmlSequenceCorpus::RENDERED.fetch(3)
    svg = Sirena.render(source_of(name), notation: :plantuml)

    expect(REXML::XPath.match(REXML::Document.new(svg), "//line").size).to eq(2)
  end

  it "refuses every other case instead of rendering part of it" do
    refused = unread_cases.map { |name| refusal(name) }

    expect(refused).to all(be_a(StandardError))
  end
end
