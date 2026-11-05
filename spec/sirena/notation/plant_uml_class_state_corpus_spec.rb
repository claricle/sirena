# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

# See the note in plant_uml_spike_spec.rb: restore the baseline registry, then
# register inside each example's isolated context.
Sirena::Notation.send(:entries).delete(:plantuml)

# The plugin corpus (claricle/metanorma-plugin-sirena#1) fixtures that used to
# be refused: class diagrams with member modifiers, member rules, notes on
# members, enum and annotation declarations, and the two state diagrams. Each
# source is the plugin fixture, verbatim.
RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  let(:svg) { Sirena.render(source, notation: :plantuml) }
  let(:root) { REXML::Document.new(svg).root }
  let(:texts) do
    REXML::XPath.match(root, "//*[local-name()='text']").map do |text|
      text.texts.map(&:value).join
    end
  end

  shared_examples "a rendered corpus fixture" do |expected|
    it "renders an svg root" do
      expect(root.name).to eq("svg")
    end

    it "draws its key text" do
      expect(texts).to include(*expected)
    end
  end

  context "with fixture 3-8, free text and rules in a class body" do
    let(:source) do
      <<~PUML
        @startuml
        class Foo1 {
          You can use
          several lines
          ..
          as you want
          and group
          ==
          things together.
          __
          You can have as many groups
          as you want
          --
          End of class
        }

        class User {
          .. Simple Getter ..
          + getName()
          + getAddress()
          .. Some setter ..
          + setName()
          __ private data __
          int age
          -- encrypted --
          String password
        }

        @enduml
      PUML
    end

    it_behaves_like "a rendered corpus fixture",
                    ["You can use", "Simple Getter", "encrypted",
                     "String password"]

    it "draws a rule for each separator and none as text" do
      expect(texts).not_to include("..", "==", "__", "--")
    end
  end

  context "with fixture 3-10, notes without an owner and with markup" do
    let(:source) do
      <<~PUML
        @startuml
        class Foo
        note left: On last defined class

        note top of Foo
          In java, <size:18>every</size> <u>class</u>
          <b>extends</b>
          <i>this</i> one.
        end note

        note as N1
          This note is <u>also</u>
          <b><color:royalBlue>on several</color>
          <s>words</s> lines
          And this is hosted by <img:sourceforge.jpg>
        end note
        @enduml
      PUML
    end

    it_behaves_like "a rendered corpus fixture",
                    ["On last defined class", "This note is also",
                     "In java, every class", "words lines"]

    it "draws no markup tag" do
      expect(texts.grep(/[<>]/)).to be_empty
    end
  end

  context "with fixture 3-11-3, modifiers and notes on members" do
    let(:source) do
      <<~PUML
        @startuml
        class A {
          {static} int counter
          +void {abstract} start(int timeoutms)
          +void {abstract} start(Duration timeout)
        }

        note left of A::counter
          This member is annotated
        end note

        note right of A::"start(int timeoutms)"
          This method with int
        end note

        note right of A::"start(Duration timeout)"
          This method with Duration
        end note
        @enduml
      PUML
    end

    it_behaves_like "a rendered corpus fixture",
                    ["int counter", "This member is annotated",
                     "This method with int", "This method with Duration"]

    it "draws both overloads" do
      expect(texts).to include("+void start(int timeoutms)",
                               "+void start(Duration timeout)")
    end
  end

  context "with fixture 3-13, enum and annotation declarations" do
    let(:source) do
      <<~PUML
        @startuml

        abstract class AbstractList
        abstract AbstractCollection
        interface List
        interface Collection

        List <|-- AbstractList
        Collection <|-- AbstractCollection

        Collection <|- List
        AbstractCollection <|- AbstractList
        AbstractList <|-- ArrayList

        class ArrayList {
          Object[] elementData
          size()
        }

        enum TimeUnit {
          DAYS
          HOURS
          MINUTES
        }

        annotation SuppressWarnings

        annotation Annotation {
          annotation with members
          String foo()
          String bar()
        }

        @enduml
      PUML
    end

    it_behaves_like "a rendered corpus fixture",
                    ["TimeUnit", "DAYS", "SuppressWarnings",
                     "Object[] elementData", "annotation with members"]
  end

  context "with fixture 3-35-4, bracketed line styles" do
    let(:source) do
      <<~PUML
        @startuml
        title Bracketed line style mix
        class foo
        class bar
        bar1 : [#red,thickness=1]
        bar2 : [#red,dashed,thickness=2]
        bar3 : [#green,dashed,thickness=4]
        bar4 : [#blue,dotted,thickness=8]
        bar5 : [#blue,plain,thickness=16]

        foo --> bar : ￿
        foo -[#red,thickness=1]-> bar1 : [#red,1]
        foo -[#red,dashed,thickness=2]-> bar2 : [#red,dashed,2]
        foo -[#green,dashed,thickness=4]-> bar3 : [#green,dashed,4]
        foo -[#blue,dotted,thickness=8]-> bar4 : [blue,dotted,8]
        foo -[#blue,plain,thickness=16]-> bar5 : [blue,plain,16]
        @enduml
      PUML
    end

    it_behaves_like "a rendered corpus fixture",
                    ["Bracketed line style mix", "bar5",
                     "[#blue,plain,thickness=16]", "[blue,dotted,8]"]

    it "dashes the dashed and dotted relations only" do
      dashed = REXML::XPath.match(root, "//*[@stroke-dasharray]").size
      expect(dashed).to eq(3)
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

    it_behaves_like "a rendered corpus fixture",
                    %w[NotShooting Idle Configuring NewValueSelection
                       NewValuePreview State1 State2 EvConfig EvNewValueSaved]
  end

  context "with fixture 9-5, aliases, descriptions and history" do
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

    it_behaves_like "a rendered corpus fixture",
                    ["State1", "Accumulate Enough Data", "Just a test",
                     "ProcessData", "H", "H*", "DeepResume",
                     "Succeeded / Save Result"]
  end
end
