# frozen_string_literal: true

require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Shared helpers for the activity specs.
module ActivityHelpers
  FIXTURES = File.expand_path("../../../../fixtures/plantuml_activity", __dir__)

  def parse(body)
    Sirena::Notation::PlantUML::Activity::Parser.new
      .parse("@startuml\n#{body}\n@enduml\n")
  end

  def layout(body)
    Sirena::Notation::PlantUML::Activity::Layout.new.call(parse(body))
  end

  def render(body)
    Sirena.render("@startuml\n#{body}\n@enduml\n", notation: :plantuml)
  end

  def render_fixture(id)
    path = File.join(FIXTURES, "plantuml-lrg-#{id}.puml")
    Sirena.render(File.read(path), notation: :plantuml)
  end

  def node(diagram, text)
    diagram.nodes.find { |n| n.text == text }
  end

  def edge(diagram, from, to)
    diagram.edges.find { |e| e.from.text == from && e.to.text == to }
  end

  def kinds(diagram)
    diagram.nodes.map(&:kind)
  end

  def labels(diagram)
    diagram.edges.map(&:label)
  end

  def svg_root(svg)
    REXML::Document.new(svg).root
  end

  def svg_texts(svg)
    REXML::XPath.match(REXML::Document.new(svg), "//text").map(&:text)
  end

  def raise_unsupported(construct)
    raise_error(Sirena::Notation::PlantUML::UnsupportedConstructError,
                /#{Regexp.escape(construct)}/)
  end
end
