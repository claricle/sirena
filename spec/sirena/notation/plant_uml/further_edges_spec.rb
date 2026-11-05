# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Reader and layout edges of the nwdiag, timing and EBNF families that the
# headline examples in further_spec.rb do not reach.
RSpec.describe Sirena::Notation::PlantUML::Further do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def render(source)
    svg = Sirena::Engine.new.render(source, notation: :plantuml)
    REXML::Document.new(svg)
    svg
  end

  def texts(source)
    render(source).scan(%r{<text[^>]*>([^<]*)</text>}).flatten
  end

  def timing(*lines)
    "@startuml\n#{lines.join("\n")}\n@enduml\n"
  end

  let(:unsupported) do
    Sirena::Notation::PlantUML::UnsupportedConstructError
  end

  describe "EBNF reader refusals" do
    def parse_error(body)
      raise_error(Sirena::Parser::ParseError, /EBNF.*#{body}/m)
    end

    it "refuses a source with no rule" do
      expect { render("@startebnf\n@endebnf\n") }.to parse_error("no rule")
    end

    it "refuses text outside the token set" do
      expect { render("@startebnf\na = \"x\" ~ ;\n@endebnf\n") }
        .to parse_error("cannot read")
    end

    it "refuses a rule that stops after its equals sign" do
      expect { render("@startebnf\na =\n@endebnf\n") }
        .to parse_error("unexpected end")
    end

    it "refuses a mark that cannot open a term" do
      expect { render("@startebnf\na = ) ;\n@endebnf\n") }
        .to parse_error("unexpected")
    end
  end

  describe "network layout and reader edges" do
    let(:shared) do
      <<~PUML
        @startuml
        nwdiag {
          address = "ignored"
          lonely
          network front {
            web [address = ".1"]
          }
          network back {
            web
            group g {
              color = "red"
              address = "ignored"
              web
            }
          }
        }
        @enduml
      PUML
    end

    it "draws a network without an address and with no node of its own" do
      expect(texts(shared)).to include("front", "back", "web", ".1")
    end

    it "skips a settings line the scope has no attribute for" do
      expect(texts(shared)).not_to include("ignored", "lonely")
    end

    it "keeps a group out of a network its members did not enter" do
      expect(render(shared)).not_to include(">g<")
    end
  end

  describe "timing reader edges" do
    it "skips presentation statements" do
      source = timing("title Ignored", 'robust "R" as R', "@0", "R is a")
      expect(texts(source)).not_to include("Ignored")
    end

    it "refuses a statement outside the subset" do
      expect { render(timing('robust "R" as R', "bogus line")) }
        .to raise_error(unsupported, /timing statement/)
    end

    it "refuses a date that is not on the calendar" do
      expect { render(timing('robust "R" as R', "@2020/13/45")) }
        .to raise_error(unsupported, /timing statement/)
    end

    it "keeps a valid colour and drops an invalid or empty one" do
      svg = render(timing('concise "C" as C', "@0", "C is a", "@50",
                          "C is b #abc;line:1x", "C is c #;line:red",
                          "highlight 0 to 50 #abc;line:red : caption"))
      expect(svg).to include("#abc")
    end

    it "captions a highlight" do
      source = timing('concise "C" as C', "@0", "C is a",
                      "highlight 0 to 50 #Gold : my caption")
      expect(texts(source)).to include("my caption")
    end

    it "draws a highlight that has no caption" do
      source = timing('concise "C" as C', "@0", "C is a",
                      "highlight 0 to 50 #Gold")
      expect(render(source)).to include("Gold")
    end

    it "reads a message without an arrival time" do
      source = timing('robust "A" as A', 'robust "B" as B', "@0", "A is x",
                      "B is y", "@10", "A -> B : go")
      expect(texts(source)).to include("go")
    end
  end

  describe "timing layout edges" do
    it "marks the time of a diagram with a single moment" do
      expect(texts(timing('robust "R" as R', "@0", "R is a"))).to include("0")
    end

    it "labels a fractional time with its fraction" do
      expect(texts(timing('robust "R" as R', "@0.5", "R is a")))
        .to include("0.5")
    end

    it "draws no head on a zero-length message" do
      source = timing('robust "A" as A', "@0", "A is x", "A -> A : self")
      expect(render(source)).not_to include("<polygon")
    end

    it "draws the clock from its offset" do
      source = timing('clock "K" as K with period 20 offset 5',
                      'binary "B" as B', "@0", "B is high", "@100",
                      "B is low")
      expect(render(source)).to include("<path")
    end

    it "draws a clock that has already started at the first time" do
      source = timing('clock "K" as K with period 20', 'binary "B" as B',
                      "@10", "B is high")
      expect(render(source)).to include("<path")
    end

    it "starts a binary track at its low level when it changes late" do
      source = timing('binary "B" as B', 'robust "R" as R', "@0", "R is a",
                      "@50", "B is high")
      expect(render(source)).to include("<path")
    end

    it "draws a binary track that changes at the first time" do
      source = timing('binary "B" as B', "@0", "B is high", "@50", "B is low")
      expect(render(source)).to include("<path")
    end

    it "leaves tracks with no change empty" do
      source = timing('robust "R" as R', 'analog "A" as A',
                      'concise "C" as C', 'binary "B" as B', "@0", "C is a")
      expect(render(source)).to include("R", "A")
    end

    it "draws an analog track holding one value" do
      expect(render(timing('analog "A" as A', "@0", "A is 3", "@10",
                           "A is 3"))).to include("<path")
    end

    it "anchors a message before its sender has a state at the track middle" do
      source = timing('robust "A" as A', 'robust "B" as B', "@0", "B is y",
                      "A -> B : early")
      expect(texts(source)).to include("early")
    end

    it "anchors a message at the state its sender holds" do
      source = timing('robust "A" as A', 'robust "B" as B', "@0", "A is x",
                      "B is y", "@10", "A -> B@30 : go")
      expect(render(source)).to include("<polygon")
    end
  end
end
