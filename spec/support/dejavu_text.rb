# frozen_string_literal: true

require "sirena/notation/plantuml/drawing"

# PlantUML specs pin the JAR's paddings, gaps and strokes. Text is measured in
# DejaVu Sans, so a text-dependent expectation is that measured advance plus
# the JAR's padding.
module DejaVuText
  FACE = Sirena::Notation::PlantUML::Drawing::Face

  def dejavu(text, size:, bold: false)
    FACE.widest_line(text, size: size, bold: bold)
  end
end
