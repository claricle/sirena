# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/drawing"

# Sequence text is measured in DejaVu Sans, the face the SVG renders in,
# not in the Lucida Grande advances the macOS JAR reports. The path stays
# because the coverage guard refuses spec deletions; the subject moved from
# Sequence::TextAdvances to Drawing::Face.
RSpec.describe "PlantUML sequence text advances", type: :task do
  let(:face) { Sirena::Notation::PlantUML::Drawing::Face }

  it "measures plain sequence text in DejaVu Sans" do
    expect(face.widest_line("transparent_keyword", size: 14))
      .to be_within(0.0001).of(148.8525)
  end

  it "measures bold sequence text in DejaVu Sans Bold" do
    expect(face.widest_line("Alice", size: 26, bold: true))
      .to be_within(0.0001).of(70.9922)
  end

  it "measures the widest explicit line instead of summing them" do
    expect(face.widest_line("longest\\nshort", size: 13))
      .to be_within(0.0001).of(47.9248)
  end
end
