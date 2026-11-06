# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

# Transitions go round the states between their ends and keep their labels
# off container titles, as PlantUML's splines do (measured with the JAR on
# plugin corpus fixtures 9-5 and 9-3-1).
RSpec.describe Sirena::Notation::PlantUML do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  let(:root) { REXML::Document.new(Sirena.render(source)).root }

  def groups(prefix)
    REXML::XPath.match(root, "//*[local-name()='g']").select do |found|
      found.attributes["id"].to_s.start_with?(prefix)
    end
  end

  def box(id)
    rect = REXML::XPath.first(groups("state-#{id}").first,
                              "*[local-name()='rect']")
    x, y, w, h = %w[x y width height].map { |name| rect.attributes[name].to_f }
    [x, y, x + w, y + h]
  end

  # Points along the transition's drawn curve.
  def curve(id)
    path = REXML::XPath.first(groups("transition-#{id}").first,
                              "*[local-name()='path']")
    commands = path.attributes["d"].scan(/[MLC][^MLC]*/)
    commands.each_with_object([]) do |command, samples|
      nums = command.scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
      samples.concat(segment(command[0], samples.last, nums))
    end
  end

  def segment(kind, from, nums)
    return [nums] if kind == "M"
    return bezier(from, nums) if kind == "C"

    (1..20).map { |step| lerp(from, nums, step / 20.0) }
  end

  def lerp(from, to, at)
    Array.new(2) { |axis| from[axis] + ((to[axis] - from[axis]) * at) }
  end

  # De Casteljau: the curve's point at each twentieth of its length.
  def bezier(from, seg)
    (1..20).map do |step|
      points = [from, seg[0..1], seg[2..3], seg[4..5]]
      points = points.each_cons(2).map do |a, b|
        lerp(a, b, step / 20.0)
      end while points.size > 1
      points.first
    end
  end

  def inside?(box, point)
    point.first.between?(box[0], box[2]) && point.last.between?(box[1], box[3])
  end

  def label(id, text)
    node = REXML::XPath.match(groups("transition-#{id}").first,
                              "*[local-name()='text']")
      .find { |t| t.texts.map(&:value).join == text }
    [node.attributes["x"].to_f, node.attributes["y"].to_f]
  end

  context "with fixture 9-5, State1 ending beyond State2 and State3" do
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

    it "bends State1's Aborted line round State2 and State3" do
      crossed = %w[State2 State3].map do |id|
        curve("State1_to_root_end").count { |pt| inside?(box(id), pt) }
      end
      expect(crossed).to eq([0, 0])
    end

    it "keeps that label off State3's title" do
      x, y = label("State1_to_root_end", "Aborted")
      title = box("State3")
      expect(inside?([title[0], title[1], title[2], title[1] + 24], [x, y]))
        .to be(false)
    end

    it "keeps Resume and DeepResume apart" do
      resume = label("State2_to_State3_history", "Resume")
      deep = label("State2_to_State3_deep_history", "DeepResume")
      expect((resume.first - deep.first).abs + (resume.last - deep.last).abs)
        .to be > 30
    end
  end

  context "with fixture 9-3-1, two composites side by side" do
    let(:source) do
      <<~PUML
        @startuml
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
          state NewValuePreview {
            State1 -> State2
          }
        }
        @enduml
      PUML
    end

    it "puts Configuring on the left of NotShooting, as PlantUML does" do
      expect(box("Configuring")[2]).to be <= box("NotShooting")[0]
    end

    it "stands Idle a rank and its label below Configuring, as PlantUML does" do
      expect(box("Idle")[1] - box("Configuring")[3]).to eq(77.0)
    end

    it "stretches NotShooting down to hold Idle" do
      expect(box("NotShooting")[3] - box("Idle")[3]).to eq(24.0)
    end

    it "draws the start marker's arrow into Idle's new place" do
      points = curve("NotShooting_start_to_Idle")
      expect(points.last[1]).to be_within(1.0).of(box("Idle")[1])
    end
  end

  context "with a state that already stands below the composite it follows" do
    let(:source) do
      <<~PUML
        @startuml
        [*] --> Outer
        state Outer {
          [*] --> A
          A --> B
          B --> C
          C --> D
          D --> E
          E --> Far
          Far --> Other : back
          Other --> Far : again
        }
        state Other {
          [*] --> Inner
        }
        @enduml
      PUML
    end

    it "leaves it where its own container put it" do
      expect(box("Far")[1] - box("Other")[3]).to be >= 77.0
    end

    it "does not grow the container beyond the state" do
      expect(box("Outer")[3] - box("Far")[3]).to eq(24.0)
    end
  end
end
