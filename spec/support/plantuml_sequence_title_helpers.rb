# frozen_string_literal: true

require "sirena/notation/plantuml/sequence"

# Helpers for the PlantUML sequence title and embedded-diagram specs.
module PlantUmlSequenceTitleHelpers
  def titled_source(*lines)
    "@startuml\n#{lines.join("\n")}\n@enduml\n"
  end

  def parsed_diagram(*lines)
    Sirena::Notation::PlantUML::Sequence::Parser.new
      .parse(titled_source(*lines))
  end

  def laid_out(*lines)
    parsed = Sirena::Notation::PlantUML::Sequence.parse(titled_source(*lines))
    parsed.transform.new.call(parsed.diagram)
  end

  def first_arrow_y(scene)
    scene.arrows.first.path[/M \S+ (\S+)/, 1].to_f
  end

  def refusal_for(*lines)
    parsed_diagram(*lines)
    nil
  rescue Sirena::Notation::PlantUML::UnsupportedConstructError => e
    e
  end

  def nested_note(*inner)
    ["A -> B", "note right", "{{", *inner, "}}", "end note"]
  end
end
