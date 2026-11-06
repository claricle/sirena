# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"
require "support/dejavu_text"

# PlantUML 1.2026.6 classic measures a participant head and a message label as
# it draws them, with creole markers taking no room: corpus 1-19 keeps Alice
# and Bob 187.4 apart under `The **Famous** Bob` and `A //well formatted//
# message`, where the raw text (markers included) gave 212.0.
RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include DejaVuText

  def gap(source)
    parsed = Sirena::Notation::PlantUML::Sequence.parse(
      "@startuml\n#{source}\n@enduml\n",
    )
    xs = parsed.transform.new.call(parsed.diagram).lifelines.map(&:x1)
    xs.last - xs.first
  end

  def labelled(label)
    "participant Alice\nparticipant Bob\nAlice -> Bob : #{label}"
  end

  def headed(title)
    "participant Alice\nparticipant \"#{title}\" as Bob\n" \
      "Alice -> Bob : hi"
  end

  let(:long) { "a rather long message label that decides the gap" }

  context "with creole in a message label" do
    it "gives an italic pair no room for its markers" do
      expect(gap(labelled("#{long} //well formatted// text")))
        .to eq(gap(labelled("#{long} well formatted text")))
    end

    it "gives a strike pair no room for its markers" do
      expect(gap(labelled("#{long} --gone-- text")))
        .to eq(gap(labelled("#{long} gone text")))
    end

    it "measures a bold run in the bold face" do
      grown = dejavu("well", size: 13, bold: true) - dejavu("well", size: 13)

      expect(gap(labelled("#{long} **well** text")) -
             gap(labelled("#{long} well text")))
        .to be_within(1e-6).of(grown)
    end

    it "measures each line of a multi-line label as drawn" do
      expect(gap(labelled("#{long} //x//\\nshort")))
        .to eq(gap(labelled("#{long} x\\nshort")))
    end
  end

  context "with creole in a participant head" do
    let(:title) { "A very long participant head title here" }

    it "gives an italic pair no room for its markers" do
      expect(gap(headed("#{title} //Famous// Bob")))
        .to eq(gap(headed("#{title} Famous Bob")))
    end

    it "measures a bold run in the bold face, half a head from the lifeline" do
      grown = dejavu("Famous", size: 14, bold: true) -
        dejavu("Famous", size: 14)

      expect(gap(headed("#{title} **Famous** Bob")) -
             gap(headed("#{title} Famous Bob")))
        .to be_within(1e-6).of(grown / 2)
    end
  end

  it "keeps a plain label exactly as wide as its glyphs" do
    wide = gap(labelled(long))
    narrow = gap(labelled("short"))

    expect(wide - narrow).to be_within(1e-6)
      .of(dejavu(long, size: 13) - dejavu("short", size: 13))
  end
end
