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

    it "drops a deactivate that closes nothing" do
      expect(activations(parse("A -> B", "deactivate B"))).to be_empty
    end

    it "drops a -- on a participant with no open bar" do
      expect(activations(parse("A -> B", "B -> C --"))).to be_empty
    end

    it "keeps the ++ of ++-- when the sender has no bar to close" do
      expect(phases.call(parse("A -> B ++--"))).to eq([:on])
    end

    it "closes the sender's bar for the -- of ++--" do
      diagram = parse("A -> B ++", "B -> C ++--")

      expect(phases.call(diagram)).to eq(%i[on on off])
    end

    it "hangs a note off a message that opened a bar" do
      diagram = parse("A -> B ++", "note right : x")

      notes = diagram.items.grep(Sirena::Notation::PlantUML::Sequence::Note)

      expect(notes.size).to eq(1)
    end

    it "reads the colour of an activation, hex or named" do
      diagram = parse("A -> B", "activate B #red", "activate B #ff8800")
      colours = activations(diagram).map(&:color)

      expect(colours).to eq(["red", "#ff8800"])
    end

    it "reads -[hidden]> in any case, either way round, as a hidden arrow" do
      lines = ["A -[hidden]> B", "A -[HIDDEN]-> B", "B <-[hidden]- A"]
      hidden = lines.map { |line| parse(line).messages.first.style.hidden }

      expect(hidden).to eq([true, true, true])
    end

    it "does not hide an ordinary arrow" do
      expect(message_of("->").style.hidden).to be(false)
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

  describe "fragment tab colours" do
    let(:header) do
      lambda do |*properties|
        ["<style>", "sequenceDiagram {", "groupHeader {", *properties, "}",
         "}", "</style>", "A -> B"]
      end
    end

    it "reads BackGroundColor and FontColor of groupHeader" do
      lines = header.call("FontColor blue", "BackGroundColor lightyellow")
      appearance = parse(*lines).appearance

      expect([appearance.tab_colour, appearance.tab_fill])
        .to eq(%w[#0000FF #FFFFE0])
    end

    it "reads a hex colour written with its hash" do
      lines = header.call("BackGroundColor #abc")

      expect(parse(*lines).appearance.tab_fill).to eq("#AABBCC")
    end

    [
      ["FontSize 0"],
      ["FontSize big"],
      ["FontColor notacolour"],
      ["FontColor add"],
      ["FontColor"],
    ].each do |properties|
      it "refuses a groupHeader holding #{properties.inspect}" do
        expect { parse(*header.call(*properties)) }
          .to raise_error(unsupported, /style block/)
      end
    end

    it "reads FontSize of groupHeader" do
      expect(parse(*header.call("FontSize 20")).appearance.tab_size).to eq(20)
    end

    [%w[group header], %w[reference header]].each do |path|
      it "reads #{path.join(' { ')} { ... } and sets nothing" do
        lines = ["<style>", "sequenceDiagram {", *path.map { |n| "#{n} {" },
                 "FontColor red", "BackGroundColor lightgreen", "}", "}", "}",
                 "</style>", "A -> B"]

        expect(parse(*lines).appearance.tab_fill).to be_nil
      end
    end

    [
      ["group {", "FontColor red"],
      ["group {", "header {", "FontSize 20"],
      ["reference {", "header {", "Shadowing true"],
    ].each do |opening|
      it "refuses #{opening.last} under #{opening.join(' ')}" do
        lines = ["<style>", "sequenceDiagram {", *opening,
                 *Array.new(opening.count { |l| l.end_with?("{") } + 1, "}"),
                 "</style>", "A -> B"]

        expect { parse(*lines) }.to raise_error(unsupported, /style block/)
      end
    end

    it "refuses a block that closes more than it opened" do
      lines = ["<style>", "sequenceDiagram {", "}", "}", "</style>"]

      expect { parse(*lines, "A -> B") }
        .to raise_error(unsupported, /style block/)
    end

    it "refuses a block that never closes its selector" do
      lines = ["<style>", "sequenceDiagram {", "</style>"]

      expect { parse(*lines, "A -> B") }
        .to raise_error(unsupported, /style block/)
    end
  end

  describe "arrow colour" do
    def style_of(arrow)
      parse("A #{arrow} B").items.first.style
    end

    it "reads a six digit colour" do
      expect(style_of("-[#22a722]>").colour).to eq("#22A722")
    end

    it "doubles the digits of a three digit colour" do
      expect(style_of("-[#f00]->").colour).to eq("#FF0000")
    end

    it "keeps the dashed shaft" do
      expect(style_of("-[#f00]->").dashed).to be(true)
    end

    it "leaves a plain arrow without a colour" do
      expect(style_of("->").colour).to be_nil
    end

    it "refuses a named colour" do
      expect { parse("A -[#red]> B") }.to raise_error(unsupported, /arrow/)
    end
  end

  describe "Maxmessagesize" do
    def limit(*lines)
      parse(*lines, "A -> B").appearance.max_message
    end

    it "reads the skinparam line" do
      expect(limit("skinparam maxmessagesize 200")).to eq(200)
    end

    it "reads the skinparam block" do
      expect(limit("skinparam {", "Maxmessagesize 200", "}")).to eq(200)
    end

    it "is nil when the source sets none" do
      expect(limit).to be_nil
    end

    it "refuses another setting in the block" do
      expect { parse("skinparam {", "Shadowing false", "}", "A -> B") }
        .to raise_error(unsupported, /Shadowing/)
    end

    it "refuses a block left open" do
      expect { parse("skinparam {", "Maxmessagesize 200", "A -> B") }
        .to raise_error(unsupported)
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
      "MinimumWidth 90\nHorizontalAlignment middle",
      "MinimumWidth wide",
      "FontStyle bold",
      "FontWeight heavy",
      "FontSize 0",
    ].each do |body|
      it "refuses the style block holding #{body.inspect}" do
        expect { parse(*style.call(body), "A -> B") }
          .to raise_error(unsupported, /style block/)
      end
    end

    it "reads the colon and semicolon form" do
      lines = style.call("MinimumWidth: 90; /* wide */")

      expect(parse(*lines, "A -> B").min_head_width).to eq(90)
    end

    it "reads the font and line of a head" do
      lines = style.call("FontColor: green; FontSize: 26; LineColor: #E00")
      head = parse(*lines, "A -> B").appearance.head_style

      expect([head.colour, head.size, head.line])
        .to eq(["#008000", 26, "#EE0000"])
    end

    it "reads the style, family and weight of a head" do
      lines = style.call("FontStyle italic\nFontName Roboto\nFontWeight 900")
      head = parse(*lines, "A -> B").appearance.head_style

      expect([head.style, head.family, head.weight])
        .to eq(%w[italic Roboto 900])
    end

    it "reads HorizontalAlignment" do
      lines = style.call("HorizontalAlignment right")

      expect(parse(*lines, "A -> B").appearance.alignment).to eq(:right)
    end

    it "aligns centre when none is written" do
      expect(parse("A -> B").appearance.alignment).to eq(:center)
    end

    it "reads a one-line style block" do
      line = "sequenceDiagram { participant { MinimumWidth 70 } }"

      expect(parse("<style>", line, "</style>", "A -> B").min_head_width)
        .to eq(70)
    end

    it "lets a later style block change one setting and keep the rest" do
      lines = [*style.call("MinimumWidth 90"),
               *style.call("HorizontalAlignment left")]

      expect(parse(*lines, "A -> B").appearance.min_width).to eq(90)
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

    {
      "->x" => [:cross, nil], "x->" => %i[filled cross],
      "<-x" => %i[filled cross], "x<-" => [:cross, nil],
      "o->" => [:filled, nil], "<->" => %i[filled filled],
      "x<->x" => %i[cross cross], "-\\" => [:upper, nil],
      "-//" => [:lower_open, nil], "-/" => [:lower, nil],
      "-\\\\" => [:upper_open, nil], "<-X" => %i[filled cross],
      "X->" => %i[filled cross], "->X" => [:cross, nil]
    }.each do |arrow, (head, tail)|
      it "reads #{arrow} as head #{head.inspect}, tail #{tail.inspect}" do
        style = parse("A #{arrow} B").messages.first.style

        expect([style.head.glyph, style.tail.glyph]).to eq([head, tail])
      end
    end

    describe "with no participant at one end" do
      def edge_message(line)
        parse("participant A", line).messages.first
      end

      {
        "[-> A : hi" => [:from, :left, false],
        "A ->] : hi" => [:to, :right, false],
        "?->A : hi" => [:from, :left, true],
        "A ->? : hi" => [:to, :right, true],
        "A <-? : hi" => [:from, :right, true],
      }.each do |line, (end_name, side, local)|
        it "reads #{line.inspect} as an edge on the #{end_name} end" do
          message = edge_message(line)
          edge = message.public_send(end_name)

          expect([edge.side, edge.local?, message.participants])
            .to eq([side, local, ["A"]])
        end
      end

      it "reads the marks written beside the edge" do
        style = edge_message("[x-> A").style

        expect([style.tail.glyph, style.head.glyph]).to eq(%i[cross filled])
      end

      it "reads a ring written beside a closing bracket" do
        expect(edge_message("A ->o]").style.head.circle).to be(true)
      end
    end

    it "reads a capital O as the ring of an o" do
      style = parse("A O-> B").messages.first.style

      expect(style.tail.circle).to be(true)
    end

    it "reads x glued to a name as part of the name" do
      expect(parse("A -> xB").messages.first.to).to eq("xB")
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
      "newpage Next" => "newpage",
      "!pragma layout smetana" => "preprocessor directive",
      "A -[#red]> B" => "message arrow",
      "[<- A" => "message arrow",
      "A <-]" => "message arrow",
      "A ->[" => "message arrow",
      "]-> A" => "message arrow",
      "[->]" => "message arrow",
      "[ -> A" => "message arrow",
      "A -> ]" => "message arrow",
      "?->?" => "message arrow",
      "A ->?B" => "message arrow",
      "A ->o?" => "message arrow",
      "[-> A ++" => "message arrow",
      "title T" => "title",
    }.each do |line, name|
      it "refuses #{line.inspect} as #{name}" do
        expect(refusal_of("A -> B", line)).to have_attributes(construct: name)
      end
    end

    it "keeps the inner boxes and drops an outer box with no members" do
      diagram = parse("box \"out\"", "box \"in1\"", "participant A", "endbox",
                      "box \"in2\"", "participant B", "endbox", "end box")

      expect(diagram.boxes.map { |b| [b.title, b.members] })
        .to eq([["in1", %w[A]], ["in2", %w[B]]])
    end

    it "keeps an outer box for the members it holds itself" do
      diagram = parse("box \"out\"", "participant A", "box \"in\"",
                      "participant B", "endbox", "end box")

      expect(diagram.boxes.map { |b| [b.title, b.members] })
        .to eq([["in", %w[B]], ["out", %w[A]]])
    end

    it "refuses an outer box whose members the inner box splits apart" do
      expect do
        parse("box", "participant A", "box", "participant B", "endbox",
              "participant C", "endbox")
      end.to raise_error(Sirena::Parser::ParseError, /neighbours/)
    end

    it "names the unclosed box when an inner one is left open" do
      expect { parse("box \"out\"", "box \"in\"", "participant A", "endbox") }
        .to raise_error(Sirena::Parser::ParseError, /"out"/)
    end

    it "reports the line of the refusal" do
      expect(refusal_of("A -> B", "newpage Next"))
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

    it "keeps the text of a note with a colour after the side" do
      expect(note_of("note right #red: x").text).to eq("x")
    end

    it "reads the colour of a note, by name or in hex" do
      fills = ["#red", "#f80", "#ff000080"].map do |colour|
        note_of("note right #{colour}: x").fill.colour
      end

      expect(fills).to eq(%w[#FF0000 #FF8800 #FF0000])
    end

    it "leaves a note without a colour with no fill" do
      expect(note_of("note right: x").fill).to be_nil
    end

    it "refuses a note colour that is not known" do
      expect { note_of("note right #nosuchcolour: x") }
        .to raise_error(unsupported, /note/)
    end

    it "attaches a note without a target to the message before it" do
      expect(note_of("note left: x")).to be_attached
    end

    it "refuses a note without a target that follows no message" do
      expect { parse("participant A", "note left: x") }
        .to raise_error(unsupported, /note/)
    end

    it "attaches a note without a target to the block that just closed" do
      diagram = parse("A -> B", "alt x", "B -> A", "end", "note right: x")

      expect(diagram.items.last).to be_attached
    end

    it "refuses a note without a target inside a block before any message" do
      expect { parse("alt x", "note right: x", "A -> B", "end") }
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

  describe "ref over" do
    let(:ref_class) { Sirena::Notation::PlantUML::Sequence::Ref }

    it "reads the targets and the text, and declares the targets" do
      diagram = parse("A -> B", "ref over B, C : see other")
      ref = diagram.items.grep(ref_class).first

      expect([ref.targets, ref.label, diagram.participants.map(&:id)])
        .to eq([%w[B C], "see other", %w[A B C]])
    end

    [
      "ref over A",
      "ref over A:",
      "ref over A : two\\nlines",
      "ref left of A : x",
    ].each do |line|
      it "refuses #{line.inspect}, which it does not draw" do
        expect(refusal_of("A -> B", line).construct).to eq("ref")
      end
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

    it "refuses a return that would answer a message from an edge" do
      expect { parse("participant A", "[-> A", "return") }
        .to raise_error(unsupported, /return/)
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

  describe "autonumber" do
    def numbers(*lines)
      parse(*lines).messages.map(&:number)
    end

    it "numbers each message from 1" do
      expect(numbers("autonumber", "A -> B : a", "B --> A : b"))
        .to eq([1, 2])
    end

    it "starts from the number it is given" do
      expect(numbers("autonumber 7", "A -> B : a")).to eq([7])
    end

    it "leaves the messages before it unnumbered" do
      expect(numbers("A -> B : a", "autonumber", "B -> A : b"))
        .to eq([nil, 1])
    end

    it "numbers a return like any other message" do
      expect(numbers("autonumber", "A -> B : a", "return b")).to eq([1, 2])
    end

    it "numbers a message that starts with &" do
      lines = ["!pragma teoz true", "autonumber", "A -> B : a", "& B -> A : b"]

      expect(numbers(*lines)).to eq([1, 2])
    end

    it "keeps a numbered message on the row of the one before it" do
      lines = ["!pragma teoz true", "autonumber", "A -> B : a", "& B -> A : b"]

      expect(parse(*lines).messages.last).to be_parallel
    end

    it "does not number without autonumber" do
      expect(numbers("A -> B : a")).to eq([nil])
    end

    {
      "a message with no label" => "A -> B",
      "a label with a line break" => "A -> B : a\\nb",
    }.each do |what, line|
      it "refuses #{what}" do
        expect { parse("autonumber", line) }
          .to raise_error(unsupported, /message arrow/)
      end
    end

    it "refuses a step, which has not been measured" do
      expect { parse("autonumber 5 10", "A -> B : a") }
        .to raise_error(unsupported, /autonumber/)
    end

    it "refuses a numbered message when Maxmessagesize is set" do
      lines = ["autonumber", "skinparam maxmessagesize 100", "A -> B : a"]

      expect { parse(*lines) }
        .to raise_error(Sirena::Parser::ParseError, /Maxmessagesize/)
    end
  end

  describe "newpage" do
    let(:page_break) { Sirena::Notation::PlantUML::Sequence::PageBreak }

    it "ends the items at the first page break" do
      items = parse("A -> B : one", "newpage", "A -> B : two").items

      expect(items.map(&:class)).to eq(
        [Sirena::Notation::PlantUML::Sequence::Message, page_break],
      )
    end

    it "keeps a participant that only a later page mentions" do
      diagram = parse("A -> B", "newpage", "C -> D")

      expect(diagram.participants.map(&:id)).to eq(%w[A B C D])
    end

    it "keeps one break for two" do
      items = parse("A -> B", "newpage", "A -> B", "newpage", "B -> A").items

      expect(items.count { |item| item.is_a?(page_break) }).to eq(1)
    end

    it "refuses a newpage inside a block" do
      expect { parse("alt a", "A -> B", "newpage", "end") }
        .to raise_error(unsupported, /newpage/)
    end

    it "refuses a newpage with a title" do
      expect { parse("A -> B", "newpage Next") }
        .to raise_error(unsupported, /newpage/)
    end
  end

  describe "note top and note bottom" do
    it "reads a one-line note after a message as a left note" do
      note = parse("A -> B", "note top: x").items.last

      expect([note.side, note.text]).to eq([:left, "x"])
    end

    it "reads note bottom after a message the same way" do
      expect(parse("A -> B", "rnote bottom: x").items.last.side).to eq(:left)
    end

    it "drops the note after a ref and keeps a warning" do
      diagram = parse("A -> B", "ref over A : r", "note top: x")

      expect([diagram.items.grep(Sirena::Notation::PlantUML::Sequence::Note),
              diagram.warnings])
        .to eq([[], ["This position is ignored: TOP"]])
    end

    it "names the position in the warning" do
      diagram = parse("A -> B", "ref over A : r", "note bottom: x")

      expect(diagram.warnings).to eq(["This position is ignored: BOTTOM"])
    end

    [
      ["note top of A: x"],
      ["note top", "x", "end note"],
      ["note top: x", "note top: y"],
    ].each do |lines|
      it "refuses #{lines.join(' / ')} after a message" do
        expect { parse("A -> B", *lines) }.to raise_error(unsupported, /note/)
      end
    end

    it "refuses a note top before any message" do
      expect { parse("note top: x", "A -> B") }
        .to raise_error(unsupported, /note/)
    end
  end

  describe "autoactivate" do
    def marks(*lines)
      activations(parse("autoactivate on", *lines))
        .map { |item| [item.phase, item.participant] }
    end

    it "activates the receiver of a call" do
      expect(marks("A -> B")).to eq([[:on, "B"]])
    end

    it "deactivates the sender of a dashed answer" do
      expect(marks("A -> B", "B --> A")).to eq([[:on, "B"], [:off, "B"]])
    end

    it "ignores a dashed message from a participant that is not active" do
      expect(marks("A --> B")).to eq([])
    end

    it "leaves a lost message alone" do
      expect(marks("A ->x B")).to eq([])
    end

    it "activates the receiver of a message with a lost tail" do
      expect(marks("A x-> B")).to eq([[:on, "B"]])
    end

    it "leaves an explicit ++ to say it once" do
      expect(marks("A -> B++")).to eq([[:on, "B"]])
    end

    it "stops after autoactivate off" do
      lines = ["autoactivate on", "A -> B", "autoactivate off", "A -> B"]

      expect(activations(parse(*lines)).size).to eq(1)
    end

    it "does nothing before autoactivate on" do
      expect(activations(parse("A -> B"))).to be_empty
    end

    it "refuses a message to the diagram edge" do
      expect { parse("autoactivate on", "participant A", "[-> A") }
        .to raise_error(unsupported, /message arrow/)
    end

    it "refuses a coloured message that has no ++" do
      expect { parse("autoactivate on", "A -> B #red") }
        .to raise_error(unsupported, /message arrow/)
    end
  end

  describe "participant fills" do
    def fill_of(token)
      parse("participant A #{token}").participants.first.fill
    end

    {
      "#transparent" => ["none", nil],
      "#FFFFFF00" => ["none", nil],
      "#CCCCCC01" => ["#CCCCCC", 0.00392],
      "#000000FE" => ["#000000", 0.99608],
      "#000000FF" => ["#000000", nil],
      "#abc" => ["#AABBCC", nil],
      "#e00" => ["#EE0000", nil],
    }.each do |token, (colour, opacity)|
      it "reads #{token} as #{colour} at #{opacity.inspect}" do
        expect([fill_of(token).colour, fill_of(token).opacity])
          .to eq([colour, opacity])
      end
    end

    it "leaves a participant without a colour unfilled" do
      expect(parse("participant A").participants.first.fill).to be_nil
    end

    it "refuses a colour name, which is not measured" do
      expect { parse("participant A #red") }
        .to raise_error(unsupported, /participant/)
    end

    it "refuses a colour on an actor" do
      expect { parse("actor A #FF0000") }
        .to raise_error(unsupported, /actor/)
    end
  end
end
