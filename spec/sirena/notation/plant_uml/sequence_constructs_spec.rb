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

  describe "create" do
    let(:lines) do
      ["A -> B : hi", "create C", "B -> C : make", "C -> A : done"]
    end

    it "reads create X as an item before the message that makes X" do
      kinds = parse(*lines).items.map { |item| item.class.name[/\w+\z/] }

      expect(kinds).to eq(%w[Message Create Message Message])
    end

    it "reads create participant X, declaring it" do
      diagram = parse("A -> B", 'create participant "Z" as Z', "B -> Z")

      expect(diagram.participants.map(&:id)).to eq(%w[A B Z])
    end

    it "finds the message that creates a participant" do
      made = sequence::Create.messages(parse(*lines).items)

      expect(made.values).to eq(["C"])
    end

    it "refuses create followed by something that is not a name" do
      expect { parse("create ???", "A -> B") }
        .to raise_error(Sirena::Notation::PlantUML::UnsupportedConstructError)
    end

    it "refuses to create a participant that already took part" do
      expect { parse("A -> B", "create B", "A -> B") }
        .to raise_error(Sirena::Notation::PlantUML::UnsupportedConstructError)
    end

    def head_top(svg, name)
      svg.xpath(%(//g[starts-with(@id,"participant-#{name}-")]/rect/@y))
        .map { |y| y.value.to_f }.min
    end

    it "draws the created head below the first row, not at the top" do
      svg = svg_of(*lines)

      expect(head_top(svg, "C")).to be > head_top(svg, "A") + 40
    end

    it "survives the typed IR" do
      expect(round_trip(parse(*lines)).items.grep(sequence::Create).size)
        .to eq(1)
    end
  end

  describe "skinparam paint" do
    it "paints the participant head fill" do
      svg = svg_of("skinparam ParticipantBackgroundColor #AA0001", "A -> B")

      expect(svg.xpath('//g[starts-with(@id,"participant-A-")]/rect/@fill')
        .map(&:value).uniq).to eq(["#AA0001"])
    end

    it "paints arrows" do
      svg = svg_of("skinparam ArrowColor #AA0004", "A -> B : x")

      expect(svg.xpath('//g[starts-with(@id,"message-")]/path/@stroke')
        .map(&:value)).to include("#AA0004")
    end

    it "reads a paint line inside a skinparam block" do
      svg = svg_of("skinparam {", "ParticipantBackgroundColor #AA0001", "}",
                   "A -> B")

      expect(svg.xpath('//g[starts-with(@id,"participant-A-")]/rect/@fill')
        .map(&:value).uniq).to eq(["#AA0001"])
    end

    it "refuses a key PlantUML does not honour" do
      expect { parse("skinparam LifeLineBorderColor #AA0001", "A -> B") }
        .to raise_error(Sirena::Notation::PlantUML::UnsupportedConstructError)
    end

    it "refuses a colour it cannot read" do
      expect { parse("skinparam ArrowColor #nonsense", "A -> B") }
        .to raise_error(Sirena::Notation::PlantUML::UnsupportedConstructError)
    end

    it "reads a thickness" do
      expect(sequence::Paint.read("ArrowThickness", "3").arrow_width).to eq("3")
    end

    it "refuses a thickness that is not a number" do
      expect(sequence::Paint.read("ArrowThickness", "x")).to be_nil
    end

    it "reads participant font colour into the head style" do
      read = sequence::Paint.read("ParticipantFontColor", "#AA0003")

      expect(read.head_style.colour).to eq("#AA0003")
    end

    it "reads group colours into the tab" do
      expect(sequence::Paint.read("SequenceGroupBackgroundColor", "#AA0009")
        .tab_fill).to eq("#AA0009")
    end
  end

  describe "arrow extras" do
    def style(arrow)
      parse(arrow).messages.first.style
    end

    it "reads several extras in one bracket" do
      s = style("A -[#red,bold]> B : x")

      expect(s.colour).to eq("#FF0000")
    end

    it "reads dashed in any order with a colour" do
      s = style("A -[dashed,#0000ff]> B : x")

      expect([s.colour, parse("A -[dashed]> B").messages.first.dashed])
        .to eq(["#0000FF", true])
    end

    it "draws dotted as a dashed shaft" do
      expect(parse("A -[dotted]> B").messages.first.dashed).to be(true)
    end

    it "leaves bold with no effect" do
      expect(parse("A -[bold]> B").messages.first.dashed).to be(false)
    end

    it "detects a diagram whose first line has bracket extras" do
      expect(sequence.sequence?("@startuml\nA -[#red,bold]> B : hi\n@enduml"))
        .to be(true)
    end

    it "refuses an extra PlantUML is not known to draw" do
      expect { parse("A -[#notacolour,bold]> B") }
        .to raise_error(Sirena::Notation::PlantUML::UnsupportedConstructError)
    end
  end

  describe "an unlabelled first row" do
    it "sits 17 below the head, as PlantUML 1.2026.6 draws it" do
      svg = svg_of("A -> B")
      bottom = svg.xpath('//g[starts-with(@id,"participant-A-")]/rect')
        .map { |r| r["y"].to_f + r["height"].to_f }.min

      expect(arrow_ys(svg).first - bottom).to be_within(0.001).of(17.0)
    end
  end

  describe "diagram detection" do
    it "treats a coloured arrow as a sequence message" do
      expect(sequence.sequence?("@startuml\nA -[#red]> B : hi\n@enduml"))
        .to be(true)
    end
  end
end
