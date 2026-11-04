# frozen_string_literal: true

require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Shared helpers for the use case and component specs.
module NodeGraphHelpers
  FIXTURES = File.expand_path("../../../../fixtures/plantuml_usecase_component",
                              __dir__)

  def parse(body, family: :usecase)
    parser = Sirena::Notation::PlantUML::NodeGraph::Parser
    direction, kind = if family == :usecase
                        %i[left_to_right actor]
                      else
                        %i[top_to_bottom interface]
                      end
    parser.new(direction: direction, default_kind: kind)
      .parse("@startuml\n#{body}\n@enduml\n")
  end

  def render(body)
    Sirena.render("@startuml\n#{body}\n@enduml\n", notation: :plantuml)
  end

  def render_fixture(name)
    Sirena.render(File.read(File.join(FIXTURES, "#{name}.puml")),
                  notation: :plantuml)
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
