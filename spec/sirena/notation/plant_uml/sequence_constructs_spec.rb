# frozen_string_literal: true

require "spec_helper"
require "nokogiri"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Sequence do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:sequence) { described_class }

  def parse(*lines)
    sequence::Parser.new.parse("@startuml\n#{lines.join("\n")}\n@enduml\n")
  end

  def round_trip(diagram)
    sequence::IRReader.call(sequence::IRAdapter.call(diagram))
  end

  def svg_of(*lines)
    Nokogiri::XML(Sirena.render("@startuml\n#{lines.join("\n")}\n@enduml\n",
                                notation: :plantuml)).tap(&:remove_namespaces!)
  end

  def arrow_ys(svg)
    svg.xpath('//g[starts-with(@id,"message-")]/path').map do |path|
      path["d"][/M [\d.]+ ([\d.]+)/, 1].to_f
    end
  end

  describe "spacing" do
    it "reads || | and ||N|| lines as spacing items" do
      items = parse("A -> B", "|||", "||||", "||45||", "B -> A").items

      expect(items.grep(sequence::Spacing).map(&:room)).to eq([25.0, 25.0,
                                                               45.0])
    end

    it "moves the next row down by the room written, as PlantUML does" do
      plain = arrow_ys(svg_of("A -> B : one", "B -> A : two"))
      spaced = arrow_ys(svg_of("A -> B : one", "|||", "||45||", "B -> A : two"))

      expect(spaced.last - plain.last).to be_within(0.001).of(70.0)
    end

    it "survives the typed IR" do
      rooms = round_trip(parse("A -> B", "||45||", "|||", "B -> A")).items
        .grep(sequence::Spacing).map(&:height)

      expect(rooms).to eq([45.0, nil])
    end
  end

  describe "participant order" do
    def ids(*lines)
      parse(*lines).participants.map(&:id)
    end

    it "seats participants left to right by order" do
      lines = ["participant B order 20", "participant A order 10"]

      expect(ids(*lines, "A -> B")).to eq(%w[A B])
    end

    it "counts a participant with no order as 0, stably" do
      lines = ["participant C", "participant B order 20",
               "participant A order -5", "participant D"]

      expect(ids(*lines, "C -> D")).to eq(%w[A C D B])
    end

    it "reads order before a colour" do
      participant = parse('participant "Zed" as Z order 3 #pink',
                          "Z -> Z").participants.first

      expect(participant.fill.colour).to eq("#FFC0CB")
    end
  end

  describe "colours" do
    it "reads a named arrow colour" do
      expect(parse("A -[#red]> B").messages.first.style.colour)
        .to eq("#FF0000")
    end

    it "refuses an arrow colour name PlantUML is not known to draw" do
      expect { parse("A -[#notacolour]> B") }
        .to raise_error(Sirena::Notation::PlantUML::UnsupportedConstructError)
    end

    it "fills a box with the colour written after its title" do
      diagram = parse('box "Team" #LightBlue', "participant A", "endbox",
                      "A -> A")

      expect(diagram.boxes.first.fill.colour).to eq("#ADD8E6")
    end

    it "keeps a box fill through the typed IR" do
      diagram = parse('box "T" #red', "participant A", "endbox", "A -> A")

      expect(round_trip(diagram).boxes.first.fill.colour).to eq("#FF0000")
    end

    it "paints the box rectangle with that colour" do
      svg = svg_of('box "T" #LightBlue', "participant A", "endbox", "A -> A")

      expect(svg.xpath('//g[starts-with(@id,"box-")]/rect/@fill').map(&:value))
        .to eq(["#ADD8E6"])
    end

    it "reads a colour name and a hex colour alike" do
      fills = %w[#pink #FFC0CB].map do |colour|
        parse("participant A #{colour}").participants.first.fill.colour
      end

      expect(fills.uniq).to eq(["#FFC0CB"])
    end

    it "reads a fully transparent colour as no fill" do
      expect(sequence::Fill.read("#transparent").colour).to eq("none")
    end
  end

  describe "autonumber" do
    it "survives the typed IR with its text and weight" do
      messages = round_trip(parse('autonumber 8 "[000]"', "A -> B : a",
                                  'autonumber "<b>0"', "B -> A : b")).messages

      expect(messages.map { |m| [m.number.to_s, m.number_weight] })
        .to eq([["[008]", nil], ["1", "bold"]])
    end

    it "gives a message with no number no weight" do
      expect(parse("A -> B : a").messages.first.number_weight).to be_nil
    end

    it "draws a plain number in the regular weight" do
      svg = svg_of('autonumber "z0"', "A -> B : a")

      expect(svg.xpath('//text[text()="z1"]').map { |t| t["font-weight"] })
        .to eq([nil])
    end

    it "measures the width a format adds to the label" do
      narrow = sequence::NumberedLabel.new(->(text) { text.length * 1.0 })
      message = parse('autonumber "[000]"', "A -> B : a").messages.first

      expect(narrow.extra(message)).to eq(5.0 + sequence::NumberedLabel::GAP)
    end
  end

  describe "diagram detection" do
    it "treats a coloured arrow as a sequence message" do
      expect(sequence.sequence?("@startuml\nA -[#red]> B : hi\n@enduml"))
        .to be(true)
    end
  end
end
