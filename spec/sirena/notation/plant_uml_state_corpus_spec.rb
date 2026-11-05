# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# The plugin corpus (claricle/metanorma-plugin-sirena) state fixtures 9-15,
# 9-3-1 and 9-5, verbatim, rendered by auto-detection as the plugin does.
RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  let(:svg) { Sirena.render(source) }
  let(:root) { REXML::Document.new(svg).root }
  let(:texts) do
    REXML::XPath.match(root, "//*[local-name()='text']").map do |text|
      text.texts.map(&:value).join
    end
  end

  # The rect each state group draws first, keyed by state id.
  def box_of(group)
    rect = REXML::XPath.first(group, "*[local-name()='rect']")
    %w[x y width height].map { |name| rect.attributes[name].to_f }
  end

  def groups_named(prefix)
    REXML::XPath.match(root, "//*[local-name()='g']").select do |group|
      group.attributes["id"].to_s.start_with?(prefix)
    end
  end

  def corners(box)
    [box[0], box[1], box[0] + box[2], box[1] + box[3]]
  end

  def inside?(inner, outer)
    inside = corners(inner)
    around = corners(outer)
    inside[0] >= around[0] && inside[1] >= around[1] &&
      inside[2] <= around[2] && inside[3] <= around[3]
  end

  def drawn_boxes
    drawn = groups_named("state-").select do |group|
      REXML::XPath.first(group, "*[local-name()='rect']")
    end
    drawn.map { |group| box_of(group) }
  end

  def contained_children(parent_id)
    parent = groups_named("state-#{parent_id}").first
    kids = REXML::XPath.match(parent, "*[local-name()='g']").select do |g|
      REXML::XPath.first(g, "*[local-name()='rect']")
    end
    [box_of(parent), kids.map { |kid| box_of(kid) }]
  end

  context "with fixture 9-15, a state diagram with notes" do
    let(:source) do
      <<~PUML
        @startuml
        [*] --> Active
        Active --> Inactive
        note left of Active : this is a short\\nnote
        note right of Inactive
          A note can also
          be defined on
          several lines
        end note
        @enduml
      PUML
    end

    it "draws both notes as text" do
      expect(texts).to include("this is a short", "several lines")
    end

    it "draws the states, not a component diagram" do
      expect(texts).to include("Active", "Inactive")
    end

    it "keeps each note out of its target" do
      nested = drawn_boxes.combination(2).any? do |one, other|
        inside?(one, other) || inside?(other, one)
      end
      expect(nested).to be(false)
    end
  end

  context "with fixture 9-3-1, nested composite states" do
    let(:source) do
      <<~PUML
        @startuml
        scale 350 width
        [*] --> NotShooting

        state NotShooting {
          [*] --> Idle
          Idle --> Configuring : EvConfig
          Configuring --> Idle : EvConfig
        }

        state Configuring {
          [*] --> NewValueSelection
          NewValueSelection --> NewValuePreview : EvNewValue
          NewValuePreview --> NewValueSelection : EvNewValueRejected
          NewValuePreview --> NewValueSelection : EvNewValueSaved

          state NewValuePreview {
            State1 -> State2
          }

        }
        @enduml
      PUML
    end

    it "draws every state and transition label" do
      expect(texts).to include("NotShooting", "Idle", "Configuring",
                               "NewValuePreview", "State1", "State2",
                               "EvConfig", "EvNewValueSaved")
    end

    it "puts Configuring at the top level, as PlantUML does" do
      expect(groups_named("state-NotShooting").first.to_s)
        .not_to include('id="state-Configuring"')
    end

    %w[NotShooting Configuring NewValuePreview].each do |name|
      it "holds the children of #{name} inside it" do
        parent, kids = contained_children(name)
        expect(kids.map do |kid|
          inside?(kid, parent)
        end).to eq(Array.new(kids.size, true))
      end

      it "gives #{name} children to hold" do
        expect(contained_children(name).last).not_to be_empty
      end
    end
  end

  context "with fixture 9-5, a composite with history and a loop" do
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

    it "draws the states and the transition labels" do
      expect(texts).to include("State3", "Accumulate Enough Data",
                               "ProcessData", "H", "H*", "Resume",
                               "DeepResume", "Failed", "Pause")
    end

    it "holds State3's children inside it" do
      parent, kids = contained_children("State3")
      expect(kids.map do |kid|
        inside?(kid, parent)
      end).to eq(Array.new(kids.size, true))
    end

    it "gives State3 its two boxes, the history marks being circles" do
      expect(contained_children("State3").last.size).to eq(2)
    end
  end
end
