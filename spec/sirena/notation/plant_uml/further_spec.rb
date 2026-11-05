# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

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

  let(:unsupported) do
    Sirena::Notation::PlantUML::UnsupportedConstructError
  end

  describe "network diagrams" do
    let(:nwdiag) do
      <<~PUML
        @startuml
        nwdiag {
          network Sample_front {
            address = "192.168.10.0/24"
            color = "red"
            // define group
            group web {
              web01 [address = ".1, .2", shape = "node"]
              web02 [address = ".2, .3"]
            }
          }
          network Sample_back {
            address = "192.168.20.0/24"
            web01 [address = ".1"]
            db01 [address = ".101", shape = database ]
            group db {
              db01;
            }
          }
        }
        @enduml
      PUML
    end

    it "draws networks, nodes and addresses" do
      expect(texts(nwdiag)).to include("Sample_front", "192.168.10.0/24",
                                       "web01", "web02", "db01", ".101")
    end

    it "paints a bar in its colour" do
      expect(render(nwdiag)).to include('fill="red"')
    end

    it "draws a node in two networks once" do
      expect(texts(nwdiag).count("web01")).to eq(1)
    end

    it "reads @startnwdiag as well" do
      source = nwdiag.sub("@startuml", "@startnwdiag")

      expect(texts(source)).to include("db01")
    end

    it "does not take a colour that could break out of an attribute" do
      source = nwdiag.sub('"red"', '"red\\" onload=\\"x"')

      expect(render(source)).not_to include("onload")
    end

    it "refuses a line outside the subset" do
      source = nwdiag.sub("// define group", "route 1.2.3.4")

      expect { render(source) }.to raise_error(unsupported, /nwdiag/)
    end

    it "refuses a block that is never closed" do
      source = nwdiag.sub(/^}\n/, "")

      expect { render(source) }.to raise_error(Sirena::Parser::ParseError)
    end
  end

  describe "timing diagrams" do
    let(:signals) do
      <<~PUML
        @startuml
        clock "Clock_1" as C1 with period 50 pulse 15 offset 10
        binary "Binary" as B
        concise "Concise" as C
        robust "Robust" as R
        analog "Analog" as A
        @0
        C is Idle
        R is Idle
        A is 0
        @100
        B is high
        C is Waiting
        R is Processing
        A is 3
        @300
        R is Waiting
        A is 1
        @enduml
      PUML
    end
    let(:conversation) do
      <<~PUML
        @startuml
        robust "Web Browser" as WB
        concise "Web User" as WU
        @0
        WU is Idle
        WB is Idle
        @100
        WU -> WB : URL
        WU is Waiting #LightCyan;line:Aqua
        @+200
        WB is Proc.
        highlight 200 to 450 #Gold;line:DimGrey : This is my caption
        @enduml
      PUML
    end
    let(:seasons) do
      <<~PUML
        @startuml
        concise "Season" as S
        scale 2592000 as 50 pixels
        @2000/11/01
        S is "Winter"
        @2001/02/01
        S is "Spring"
        @enduml
      PUML
    end

    it "labels every participant kind and its states" do
      expect(texts(signals)).to include("Clock_1", "Binary", "Concise",
                                        "Waiting", "Processing", "3.0")
    end

    it "marks the times of the changes on the axis" do
      expect(texts(signals)).to include("0", "100", "300")
    end

    it "draws a message and a highlight caption" do
      expect(texts(conversation)).to include("URL", "This is my caption")
    end

    it "resolves a relative time against the previous one" do
      expect(texts(conversation)).to include("300")
    end

    it "fills a concise state in the colour it names" do
      expect(render(conversation)).to include('fill="LightCyan"')
    end

    it "shades a highlight in its colour" do
      expect(render(conversation)).to include('fill="Gold"')
    end

    it "labels a dated axis" do
      expect(texts(seasons)).to include("Winter", "11/01", "02/01")
    end

    it "refuses a participant that was never declared" do
      source = "@startuml\nconcise \"A\" as A\n@0\nB is x\n@enduml\n"

      expect { render(source) }.to raise_error(unsupported, /timing/)
    end

    it "refuses a clock with no period" do
      expect { render("@startuml\nclock C\n@enduml\n") }
        .to raise_error(unsupported)
    end
  end

  describe "EBNF diagrams" do
    let(:railroad) do
      <<~PUML
        @startebnf "My Number"
        My_Number = "1 - 9", [{"0 - 9"}-] ;
        @endebnf
      PUML
    end
    let(:grammar) do
      <<~PUML
        @startebnf
        (* a comment *)
        sign = "+" | "-" ;
        number = [sign], digit, { digit } ;
        digit = ( "0" | "1" ), ? special ? ;
        @endebnf
      PUML
    end

    it "labels the rule and its terminals" do
      expect(texts(railroad)).to include("My_Number", "1 - 9", "0 - 9")
    end

    it "draws the loop and skip rails as paths" do
      expect(render(railroad)).to include("<path")
    end

    it "draws every rule of a grammar" do
      expect(texts(grammar)).to include("sign", "number", "digit", "special")
    end

    it "refuses a rule that is not closed" do
      expect { render("@startebnf\na = \"x\"\n@endebnf\n") }
        .to raise_error(Sirena::Parser::ParseError, /EBNF/)
    end
  end

  describe "detection" do
    it "claims a @startebnf opener" do
      expect(Sirena::Notation::PlantUML.claims?("@startebnf\n")).to be(true)
    end

    it "claims a @startnwdiag opener" do
      expect(Sirena::Notation::PlantUML.claims?("@startnwdiag\n")).to be(true)
    end

    it "leaves a sequence diagram with arrows to the sequence family" do
      expect(texts("@startuml\nAlice -> Bob : hi\n@enduml\n")).to include("hi")
    end
  end
end
