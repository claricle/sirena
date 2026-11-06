# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  let(:root) { REXML::Document.new(Sirena.render(source)).root }

  def box(id)
    group = REXML::XPath.match(root, "//*[local-name()='g']").find do |found|
      found.attributes["id"] == "state-#{id}"
    end
    rect = REXML::XPath.first(group, "*[local-name()='rect']")
    x, y, w, h = %w[x y width height].map { |name| rect.attributes[name].to_f }
    [x, y, x + w, y + h]
  end

  def note_text_x
    note = REXML::XPath.match(root, "//*[local-name()='g']").find do |found|
      found.attributes["id"] == "state-Idle----note0"
    end
    REXML::XPath.first(note, ".//*[local-name()='text']")
      .attributes["x"].to_f
  end

  context "with fixture 9-5, whose labels crowd the ranks of State2" do
    let(:source) do
      <<~PUML
        @startuml
        [*] -> State1
        State1 --> State2 : Succeeded
        State1 --> [*] : Aborted
        State2 --> State3 : Succeeded
        State2 --> [*] : Aborted
        state State3 {
          state "Accumulate Enough Data" as long1
          long1 : Just a test
          [*] --> long1
          long1 --> long1 : New Data
          long1 --> ProcessData : Enough Data
          State2 --> [H]: Resume
        }
        State3 --> State2 : Pause
        State2 --> State3[H*]: DeepResume
        State3 --> State3 : Failed
        State3 --> [*] : Succeeded / Save Result
        State3 --> [*] : Aborted
        @enduml
      PUML
    end

    it "stands State2 right of State3, as graphviz does" do
      expect(box("State2").first).to be > box("State3")[2]
    end

    it "stands State1 right of State2" do
      expect(box("State1").first).to be > box("State2")[2]
    end

    it "keeps State2 above State3" do
      expect(box("State2").last).to be < box("State3")[1]
    end
  end

  context "with a noted state beside a composite that moves it" do
    let(:source) do
      <<~PUML
        @startuml
        [*] --> Idle
        Idle --> Box : go
        note right of Idle : remember
        state Box {
          [*] --> Inner
        }
        Box --> Idle : back
        Box --> [*] : done
        @enduml
      PUML
    end

    it "carries the note along with its state" do
      expect(note_text_x - box("Idle")[2]).to be_within(2.0).of(36.0)
    end
  end

  context "with a transition without a label that skips a rank" do
    let(:source) do
      <<~PUML
        @startuml
        [*] --> A
        A --> B
        B --> Box
        A --> Box
        state Box {
          [*] --> Inner
        }
        @enduml
      PUML
    end

    it "stands the states of the chain below one another" do
      expect(%w[A B Box].map { |id| box(id)[1] }).to eq(
        %w[A B Box].map { |id| box(id)[1] }.sort,
      )
    end
  end

  context "with a diagram that has no composite" do
    let(:source) do
      <<~PUML
        @startuml
        [*] --> A
        A --> B : go
        @enduml
      PUML
    end

    it "leaves the states in a column" do
      expect(box("A").first).to eq(box("B").first)
    end
  end
end
