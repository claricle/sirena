# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

module PlantUmlSequenceHelpers
  def wrap(*lines)
    "@startuml\n#{lines.join("\n")}\n@enduml\n"
  end

  def parse(*lines)
    Sirena::Notation::PlantUML::Sequence::Parser.new.parse(wrap(*lines))
  end

  def refusal_of(*lines)
    parse(*lines)
    nil
  rescue Sirena::Notation::PlantUML::UnsupportedConstructError => e
    e
  end

  def activations(diagram)
    diagram.items.grep(Sirena::Notation::PlantUML::Sequence::Activation)
  end

  def message_of(arrow)
    parse("A #{arrow} B : hi").messages.first
  end
end

RSpec.describe Sirena::Notation::PlantUML::Sequence::Parser do
  include PlantUmlSequenceHelpers

  let(:unsupported) do
    Sirena::Notation::PlantUML::UnsupportedConstructError
  end

  describe "pragmas" do
    it "accepts !pragma teoz true and keeps the messages" do
      diagram = parse("!pragma teoz true", "A -> B : hi")

      expect(diagram.messages.size).to eq(1)
    end

    it "still refuses another pragma by name" do
      expect { parse("!pragma layout smetana", "A -> B") }
        .to raise_error(unsupported, /preprocessor directive/)
    end
  end

  describe "parallel lines" do
    def parallel_flags(*lines)
      parse("!pragma teoz true", *lines).items.map(&:parallel?)
    end

    it "marks a message, a note and a block that start with &" do
      lines = ["A -> B", "& B -> A", "& note over A: n", "& opt", "end"]

      expect(parallel_flags(*lines)).to eq([false, true, true, true, false])
    end

    it "reads the note body of a block note that starts with &" do
      note = parse("!pragma teoz true", "A -> B", "& note over A", "x",
                   "end note").items.last

      expect([note.parallel?, note.text]).to eq([true, "x"])
    end

    it "marks a message written after a closed block" do
      expect(parallel_flags("opt", "A -> B", "end", "& A -> B").last)
        .to be(true)
    end

    it "keeps the activation written on a parallel message" do
      diagram = parse("!pragma teoz true", "A -> B", "& B -> C ++")

      expect(activations(diagram).map(&:participant)).to eq(["C"])
    end

    {
      "without the teoz pragma" => ["A -> B", "& B -> A"],
      "with nothing to share a row with" => ["!pragma teoz true", "& A -> B"],
      "after a divider" => ["!pragma teoz true", "A -> B", "== d ==",
                            "& B -> A"],
      "before something that takes no row" => ["!pragma teoz true", "A -> B",
                                               "& activate A"],
    }.each do |situation, lines|
      it "refuses & #{situation} as a parallel message" do
        expect(refusal_of(*lines))
          .to have_attributes(construct: "parallel message")
      end
    end
  end

  describe "hide footbox" do
    it "keeps the foot heads by default" do
      expect(parse("A -> B").footbox?).to be(true)
    end

    it "drops the foot heads after hide footbox" do
      expect(parse("hide footbox", "A -> B").footbox?).to be(false)
    end

    it "reads it in any case and after the messages" do
      expect(parse("A -> B", "HIDE Footbox").footbox?).to be(false)
    end

    it "still refuses another hide by name" do
      expect(refusal_of("hide unlinked", "A -> B"))
        .to have_attributes(construct: "hide")
    end
  end

  describe "activation" do
    let(:phases) do
      ->(diagram) { diagram.items.grep(Sirena::Notation::PlantUML::Sequence::Activation).map(&:phase) }
    end

    it "reads activate and deactivate" do
      diagram = parse("A -> B", "activate B", "deactivate B")

      expect(phases.call(diagram)).to eq(%i[on off])
    end

    it "reads ++ as activating the receiver" do
      expect(phases.call(parse("A -> B ++"))).to eq([:on])
    end

    it "reads --++ as deactivating then activating" do
      diagram = parse("A -> B ++", "B -> A --++")

      expect(phases.call(diagram)).to eq(%i[on off on])
    end

    it "refuses a deactivate that closes nothing" do
      expect { parse("A -> B", "deactivate B") }
        .to raise_error(unsupported, /deactivate/)
    end

    it "reads the colour of an activation, hex or named" do
      diagram = parse("A -> B", "activate B #red", "activate B #ff8800")
      colours = activations(diagram).map(&:color)

      expect(colours).to eq(["red", "#ff8800"])
    end

    it "gives the colour on a message line to the bar ++ opens" do
      diagram = parse("A -> B ++ #green : hi", "B -> A --++ #blue")
      colours = activations(diagram).map { |a| [a.phase, a.color] }

      expect(colours).to eq([[:on, "green"], [:off, nil], [:on, "blue"]])
    end

    {
      "A -> B ++ #notacolour" => /message arrow/,
      "A -> B #red" => /message arrow/,
      "A -> B -- #red" => /message arrow/,
    }.each do |line, message|
      it "refuses #{line.inspect}, which colours no bar" do
        expect { parse("A -> B ++", line) }
          .to raise_error(unsupported, message)
      end
    end

    it "refuses a colour on deactivate" do
      expect { parse("A -> B ++", "deactivate B #red") }
        .to raise_error(unsupported, /deactivate/)
    end
  end

  describe "destroy" do
    let(:destroyed) do
      lambda do |diagram|
        diagram.items.grep(Sirena::Notation::PlantUML::Sequence::Destroy)
          .map(&:participant)
      end
    end

    it "reads destroy X" do
      expect(destroyed.call(parse("A -> B", "destroy B"))).to eq(["B"])
    end

    it "reads !! as destroying the receiver of the message" do
      expect(destroyed.call(parse("A -> B !!", "B <- A !!"))).to eq(%w[B B])
    end

    it "refuses destroy with no participant" do
      expect { parse("A -> B", "destroy") }
        .to raise_error(unsupported, /destroy/)
    end
  end

  describe "stereotypes" do
    it "reads <<text>> after a participant declaration" do
      participant = parse('participant "C" as C <<st>>').participants.first

      expect([participant.id, participant.stereotype]).to eq(%w[C st])
    end

    it "leaves the stereotype nil when none is written" do
      expect(parse("participant C").participants.first.stereotype).to be_nil
    end

    it "refuses a stereotype on an actor, which has a figure to draw" do
      expect { parse("actor C <<st>>") }.to raise_error(unsupported, /actor/)
    end
  end

  describe "minimum participant width" do
    let(:style) do
      lambda do |body|
        ["<style>", "sequenceDiagram {", "participant {", body, "}", "}",
         "</style>"]
      end
    end

    it "reads skinparam MinClassWidth" do
      expect(parse("skinparam MinClassWidth 100", "A -> B").min_head_width)
        .to eq(100)
    end

    it "reads MinimumWidth in a style block" do
      lines = style.call("MinimumWidth 90")

      expect(parse(*lines, "A -> B").min_head_width).to eq(90)
    end

    it "accepts HorizontalAlignment center beside it" do
      lines = style.call("MinimumWidth 90\nHorizontalAlignment center")

      expect(parse(*lines, "A -> B").min_head_width).to eq(90)
    end

    it "is nil when the source asks for none" do
      expect(parse("A -> B").min_head_width).to be_nil
    end

    [
      "MinimumWidth 90\nHorizontalAlignment right",
      "MinimumWidth 90\nFontColor red",
      "FontColor red",
      "MinimumWidth wide",
    ].each do |body|
      it "refuses the style block holding #{body.inspect}" do
        expect { parse(*style.call(body), "A -> B") }
          .to raise_error(unsupported, /style block/)
      end
    end

    it "refuses a style block for another element" do
      other = ["<style>", "note {", "FontColor red", "}", "</style>"]

      expect { parse(*other, "A -> B") }
        .to raise_error(unsupported, /style block/)
    end

    it "does not read @enduml inside a style block that never closes" do
      expect { parse("<style>", "A -> B") }
        .to raise_error(Sirena::Parser::ParseError, /@enduml/)
    end

    it "refuses another skinparam by name" do
      expect { parse("skinparam MinClassWidth", "A -> B") }
        .to raise_error(unsupported, /skinparam/)
    end
  end

  describe "participants" do
    {
      "participant" => :participant, "actor" => :actor,
      "boundary" => :boundary, "control" => :control, "entity" => :entity,
      "database" => :database, "collections" => :collections,
      "queue" => :queue, "Actor" => :actor
    }.each do |word, kind|
      it "reads #{word} as #{kind}" do
        expect(parse("#{word} A").participants.first.kind).to eq(kind)
      end
    end

    it "reads `X as Y` as label X and id Y" do
      participant = parse('participant "Long name" as L').participants.first

      expect([participant.label, participant.id]).to eq(["Long name", "L"])
    end

    it "orders participants by first mention, declared or not" do
      ids = parse("A -> B", "participant C", "C -> A").participants.map(&:id)

      expect(ids).to eq(%w[A B C])
    end

    it "keeps the first declaration when a name is declared twice" do
      kinds = parse("actor A", "participant A").participants.map(&:kind)

      expect(kinds).to eq([:actor])
    end
  end

  describe "messages" do
    {
      "->" => [:filled, false], "->>" => [:open, false],
      "-->" => [:filled, true], "-->>" => [:open, true]
    }.each do |arrow, (head, dashed)|
      it "reads #{arrow} as head #{head}, dashed #{dashed}" do
        message = message_of(arrow)

        expect([message.head, message.dashed]).to eq([head, dashed])
      end
    end

    {
      "<-" => [:filled, false], "<<-" => [:open, false],
      "<--" => [:filled, true], "<<--" => [:open, true]
    }.each do |arrow, (head, dashed)|
      it "reads #{arrow} as the reverse, head #{head}, dashed #{dashed}" do
        message = message_of(arrow)

        expect([message.from, message.to, message.head, message.dashed])
          .to eq(["B", "A", head, dashed])
      end
    end

    it "keeps the label as written" do
      expect(message_of("->").label).to eq("hi")
    end

    it "reads a message with no label" do
      expect(parse("A -> B").messages.first.label).to be_nil
    end

    it "reads a self message" do
      expect(parse("A -> A").messages.first).to be_self_message
    end

    it "reads a quoted endpoint without its quotes" do
      expect(parse('"A b" -> C').messages.first.from).to eq("A b")
    end
  end

  describe "boxes" do
    it "groups the participants declared inside" do
      box = parse('box "G"', "participant A", "endbox", "A -> B").boxes.first

      expect([box.title, box.members]).to eq(["G", ["A"]])
    end

    it "reads `end box` as the closer" do
      expect(parse("box", "participant A", "end box").boxes.size).to eq(1)
    end
  end

  describe "the wrapper" do
    it "skips comment lines and blank lines" do
      expect(parse("' note", "", "A -> B").messages.size).to eq(1)
    end

    it "refuses a diagram with no participant" do
      expect { parse("' nothing") }.to raise_error(unsupported, /empty/)
    end

    it "refuses a missing @enduml" do
      expect { described_class.new.parse("@startuml\nA -> B\n") }
        .to raise_error(Sirena::Parser::ParseError, /@enduml/)
    end

    it "refuses invalid UTF-8" do
      expect { described_class.new.parse("@startuml\nA -> \xFF\n@enduml") }
        .to raise_error(Sirena::Parser::ParseError, /UTF-8/)
    end

    it "refuses an unclosed box" do
      expect { parse("box", "participant A") }
        .to raise_error(Sirena::Parser::ParseError, /never closed/)
    end

    it "refuses a box around separated participants" do
      lines = ["A -> B", "box", "participant C", "participant A", "end box"]

      expect { parse(*lines) }
        .to raise_error(Sirena::Parser::ParseError, /neighbours/)
    end
  end

  describe "constructs outside the slice" do
    {
      "newpage" => "newpage",
      "!pragma layout smetana" => "preprocessor directive",
      "A ->x B" => "message arrow", "A -[#red]> B" => "message arrow",
      "title T" => "title"
    }.each do |line, name|
      it "refuses #{line.inspect} as #{name}" do
        expect(refusal_of("A -> B", line)).to have_attributes(construct: name)
      end
    end

    it "refuses a nested box" do
      expect { parse("box", "box", "participant A") }
        .to raise_error(unsupported, /nested box/)
    end

    it "reports the line of the refusal" do
      expect(refusal_of("A -> B", "newpage"))
        .to have_attributes(line: 3)
    end
  end

  describe "notes" do
    def note_of(*lines)
      parse("A -> B", *lines).items.last
    end

    it "reads a one-line note over a participant" do
      note = note_of("note over A: hi")

      expect([note.side, note.targets, note.text]).to eq([:over, ["A"], "hi"])
    end

    it "reads a note over two participants" do
      expect(note_of("note over A, B: hi").targets).to eq(%w[A B])
    end

    it "joins the lines of a block note and keeps its comment-like lines" do
      note = note_of("note right of B", "one", "' two", "end note")

      expect(note.text).to eq("one\n' two")
    end

    it "reads hnote and rnote shapes" do
      shapes = %w[hnote rnote].map do |word|
        note_of("#{word} left of A: x").shape
      end

      expect(shapes).to eq(%i[hnote rnote])
    end

    it "reads a note across all participants" do
      expect(note_of("note across: x").side).to eq(:across)
    end

    it "ignores a colour after the side" do
      expect(note_of("note right #red: x").text).to eq("x")
    end

    it "attaches a note without a target to the message before it" do
      expect(note_of("note left: x")).to be_attached
    end

    it "refuses a note without a target that follows no message" do
      expect { parse("participant A", "note left: x") }
        .to raise_error(unsupported, /note/)
    end

    it "reads @enduml inside an open note as note text" do
      expect { parse("A -> B", "note left of A", "text") }
        .to raise_error(Sirena::Parser::ParseError, /missing @enduml/)
    end

    it "splits the characters backslash-n into lines" do
      expect(note_of("note over A: a\\nb").lines).to eq(%w[a b])
    end
  end

  describe "blocks" do
    def phases(*lines)
      fragment = Sirena::Notation::PlantUML::Sequence::Fragment
      parse("A -> B", *lines).items.grep(fragment)
        .map { |f| [f.phase, f.keyword, f.label] }
    end

    it "reads alt, else and end with their guards" do
      expect(phases("alt ok", "else bad", "end"))
        .to eq([[:open, "alt", "ok"], [:else, "alt", "bad"],
                [:close, "alt", nil]])
    end

    it "reads every block keyword" do
      words = %w[opt loop par critical break group]

      expect(words.map { |w| phases(w, "end").first[1] }).to eq(words)
    end

    it "drops the colour of a group" do
      expect(phases("group #ffa Setup", "end").first[2]).to eq("Setup")
    end

    it "nests blocks" do
      expect(phases("alt", "loop", "end", "end").map(&:first))
        .to eq(%i[open open close close])
    end

    it "refuses an end with nothing open" do
      expect { parse("A -> B", "end") }.to raise_error(unsupported, /end/)
    end

    it "refuses an else outside a block" do
      expect { parse("A -> B", "else") }.to raise_error(unsupported, /else/)
    end

    it "refuses a block that is never closed" do
      expect { parse("A -> B", "alt x") }
        .to raise_error(Sirena::Parser::ParseError, /block is never closed/)
    end
  end

  describe "return and dividers" do
    it "answers the last call with a dashed message the other way" do
      reply = parse("A -> B", "return ok").messages.last

      expect([reply.from, reply.to, reply.dashed, reply.label])
        .to eq(["B", "A", true, "ok"])
    end

    it "answers nested calls in reverse order" do
      senders = parse("A -> B", "B -> C", "return", "return").messages.last(2)

      expect(senders.map(&:from)).to eq(%w[C B])
    end

    it "refuses a return with nothing to answer" do
      expect { parse("A --> B", "return") }
        .to raise_error(unsupported, /return/)
    end

    it "reads a divider with its text" do
      divider = parse("A -> B", "== Phase ==").items.last

      expect(divider.label).to eq("Phase")
    end
  end
end
