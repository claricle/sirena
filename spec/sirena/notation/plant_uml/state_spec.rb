# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::State do
  def wrap(*lines)
    "@startuml\n#{lines.join("\n")}\n@enduml\n"
  end

  def model(*lines)
    described_class::Reader.new.parse(wrap(*lines))
  end

  describe ".state?" do
    it "claims a source with a state declaration" do
      expect(described_class.state?(wrap("state A", "A --> B"))).to be(true)
    end

    it "claims a source with a start marker" do
      expect(described_class.state?(wrap("[*] --> A"))).to be(true)
    end

    it "leaves a class diagram alone" do
      expect(described_class.state?(wrap("class A", "[*] --> A"))).to be(false)
    end

    it "leaves a sequence diagram alone" do
      expect(described_class.state?(wrap("A -> B : hi"))).to be(false)
    end
  end

  describe "the reader" do
    it "starts at the scope's start marker and ends at its end marker" do
      diagram = model("[*] --> A", "A --> [*]")

      expect(diagram.states.map(&:state_type)).to eq(%w[start normal end])
    end

    it "puts a state first mentioned in a body inside it" do
      diagram = model("state P {", "A --> B", "}")

      expect(diagram.find_state("P").children.map(&:id)).to eq(%w[A B])
    end

    it "labels an alias and keeps its description under it" do
      state = model('state "Long name" as L', "L : detail").find_state("L")

      expect([state.label, state.descriptions])
        .to eq(["Long name", ["Long name", "detail"]])
    end

    it "reads a reversed arrow as a transition the other way" do
      transition = model("A <-- B : back").transitions.first

      expect([transition.from_id, transition.to_id, transition.trigger])
        .to eq(["B", "A", "back"])
    end

    it "draws history as a small state of its scope" do
      diagram = model("state P {", "[*] --> A", "A --> [H]", "}")

      expect(diagram.find_state("P_history")).to have_attributes(label: "H")
    end

    it "refuses a line outside the subset" do
      expect { model("note left of A") }.to raise_error(
        Sirena::Notation::PlantUML::UnsupportedConstructError,
        /state statement/,
      )
    end

    it "refuses a body that is never closed" do
      expect { model("state P {", "A --> B") }
        .to raise_error(Sirena::Parser::ParseError, /never closed/)
    end
  end
end
