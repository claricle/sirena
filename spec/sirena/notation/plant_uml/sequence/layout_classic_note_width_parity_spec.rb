# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"
require "support/dejavu_text"

# PlantUML 1.2026.6 classic never moves a lifeline for a note: corpus 1-15
# keeps Alice and Bob 52.7 apart under a 215-wide right-hand note, and 1-19
# 187.4 apart under three notes. The note overlaps its neighbours and only
# grows the canvas. A note is as wide as it is drawn: in the skin's 13px face,
# with creole markers taking no room.
RSpec.describe Sirena::Notation::PlantUML::Sequence::Layout do
  include DejaVuText

  let(:pad) { Sirena::Notation::PlantUML::Sequence::NoteGeometry::PAD }
  let(:heads) { "participant Alice\nparticipant Bob\n" }

  def scene_of(source, theme: nil)
    parsed = Sirena::Notation::PlantUML::Sequence.parse(
      "@startuml\n#{source}\n@enduml\n",
    )
    transform = parsed.transform.new
    transform.theme = theme if theme
    transform.call(parsed.diagram)
  end

  def gauge(source)
    lifelines = scene_of(source).lifelines.map(&:x1)
    lifelines.map { |x| (x - lifelines.first).round(4) }
  end

  def note_width(source, **options)
    xs = scene_of(source, **options).notes.first.path
      .scan(/-?\d+(?:\.\d+)?/).map(&:to_f).each_slice(2).map(&:first)
    xs.max - xs.min
  end

  def over_both(text)
    "#{heads}note over Alice, Bob: #{text}"
  end

  context "with a note wider than the heads" do
    {
      "right of the first participant" =>
        "note right of Alice: a right note much wider than the heads",
      "left of the second participant" =>
        "note left of Bob: a left note much wider than the heads",
      "over both participants" =>
        "note over Alice, Bob: a note over both much wider than the heads",
    }.each do |place, note|
      it "keeps the participants where the heads put them, #{place}" do
        expect(gauge(heads + note)).to eq(gauge(heads))
      end
    end

    it "keeps the participants where the heads put them, on a message" do
      messaged = "#{heads}Alice -> Bob: hi\n"

      expect(gauge("#{messaged}note right: a note wider than the heads"))
        .to eq(gauge(messaged))
    end

    it "grows the canvas to hold a note that sticks out on the right" do
      noted = scene_of("#{heads}note right of Alice: #{'wide ' * 12}end")

      expect(noted.width).to be > scene_of(heads).width + 200
    end
  end

  context "with creole in a note line" do
    it "measures a wave tag as the text it wraps" do
      width = note_width("#{heads}note over Alice, Bob\n" \
                         "<w:#FF33FF>This is hosted</w> by\nend note")

      expect(width).to eq(dejavu("This is hosted by", size: 13) + (2 * pad))
    end

    it "measures a bold pair in the bold face" do
      width = note_width(over_both("**hello** you"))
      text = dejavu("hello", size: 13, bold: true) + dejavu(" you", size: 13)

      expect(width).to eq(text + (2 * pad))
    end

    it "measures a size run at its own size" do
      width = note_width(over_both("a <size:18>big</size> run"))
      text = dejavu("a ", size: 13) + dejavu("big", size: 18) +
        dejavu(" run", size: 13)

      expect(width).to be_within(1e-6).of(text + (2 * pad))
    end

    it "measures an undecoded image as monospace text" do
      width = note_width(over_both("<img missing.png>"))
      mono = Sirena::TextMeasurement.measure_mono("(Cannot decode)",
                                                  font_size: 13)

      expect(width).to eq(mono[:width] + (2 * pad))
    end

    it "measures an empty line as no text" do
      width = note_width("#{heads}note right of Alice: b\\n\\na")

      expect(width).to eq(dejavu("b", size: 13) + (2 * pad))
    end
  end

  it "measures a note in the theme's own size when a theme paints it" do
    theme = Sirena::Theme::Registry.get(:light)
    size = theme.typography.font_size_normal.to_f
    width = note_width(over_both("a long enough note text"), theme: theme)

    expect(width).to eq(dejavu("a long enough note text",
                               size: size) + (2 * pad))
  end
end
