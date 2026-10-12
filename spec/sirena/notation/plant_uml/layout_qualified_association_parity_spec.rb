# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def case_result(id)
    root = "spec/plantuml"
    reference = "#{root}/references/class/#{id}.svg"
    SpecSupport::LayoutParity::CaseComparator.compare(
      case_id: id, type: "plantuml_class", reference: reference,
      reference_svg: File.read(reference),
      sirena_svg: Sirena.render(File.read("#{root}/class/#{id}.puml"),
                                notation: :plantuml),
      reproduce: __FILE__,
      recognizer: SpecSupport::LayoutParity::PlantumlClassRecognizer.new,
      spatial_kinds: [:class]
    )
  end

  def render_case(id)
    path = "spec/plantuml/class/#{id}.puml"
    REXML::Document.new(Sirena.render(File.read(path), notation: :plantuml))
  end

  def box_signature(document, name)
    group = REXML::XPath.first(document, "//g[@id='class-#{name}']")
    rows = REXML::XPath.match(group, "text").map(&:text)
    height = REXML::XPath.first(group, "rect").attributes["height"].to_f
    [rows, height]
  end

  {
    "resources.vega.nonreg.simple.QualifiedAssoc001--8c3b78057dc3" => 25,
    "resources.vega.nonreg.simple.QualifiedAssoc002--d57fb49a9920" => 11,
    "resources.vega.svg.interactive.SVG0006_Svek--70f5757ed2ca" => 11,
  }.each do |id, matched|
    it "recognizes every pinned element in #{id}" do
      result = case_result(id)

      expect([result.hard_failure?, result.geometry[:matched]])
        .to eq([false, matched])
    end
  end

  it "draws qualifier and multiline text without source delimiters" do
    id = "resources.vega.nonreg.simple.QualifiedAssoc002--d57fb49a9920"
    texts = REXML::XPath.match(render_case(id), "//text").map(&:text)
    wanted = ["customerId: long", "customer", "1"]

    expect([wanted.all? { |text| texts.include?(text) },
            texts.grep(/\A\[|\\n/)]).to eq([true, []])
  end

  it "draws generic arguments as PlantUML's floating title text" do
    id = "resources.vega.nonreg.simple.QualifiedAssoc001--8c3b78057dc3"

    expect(box_signature(render_case(id), "HashMap"))
      .to eq([%w[HashMap K,V], 46.0])
  end
end
