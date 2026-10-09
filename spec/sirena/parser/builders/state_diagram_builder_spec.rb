# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::StateDiagram do
  subject(:diagram) { described_class.new.apply(tree) }

  def ids(states)
    states.map(&:id)
  end

  context "with a header-only hash" do
    let(:tree) { { header: "stateDiagram-v2" } }

    it "produces an empty diagram" do
      expect(diagram.states).to be_empty
    end
  end

  context "with a lone direction hash" do
    let(:tree) { { direction: { dir_value: "LR" } } }

    it "sets the direction" do
      expect(diagram.direction).to eq("LR")
    end
  end

  context "with a lone transition hash and noise in an array" do
    it "processes a hash tree directly" do
      d = described_class.new.apply({ from: "A", to: "B" })
      expect(ids(d.states)).to eq(%w[A B])
    end

    it "ignores non-hash array entries" do
      d = described_class.new.apply(["noise", { from: "A", to: "B" }])
      expect(d.transitions.size).to eq(1)
    end
  end

  context "with start and end markers" do
    let(:tree) do
      [
        { from: "[*]", to: "A" },
        { from: "A", to: "[*]" },
        { from: "[*]", to: { marker_type: "[*]" } },
      ]
    end

    it "creates one start and one end state and reuses them",
       :aggregate_failures do
      expect(diagram.states.map(&:state_type)).to eq(%w[start normal end])
      expect(diagram.transitions.map { |t| [t.from_id, t.to_id] })
        .to eq([%w[start_1 A], %w[A end_2], %w[start_1 end_2]])
    end
  end

  context "with chained transitions" do
    let(:tree) do
      [
        { from: "A", to: "B",
          chain: [{ chain_to: "C" }, { other: 1 }, { chain_to: "D" }] },
        { from: "X", to: "Y", chain: [] },
      ]
    end

    it "links each chain target to the previous, skipping malformed items" do
      pairs = diagram.transitions.map { |t| [t.from_id, t.to_id] }
      expect(pairs).to eq([%w[A B], %w[B C], %w[C D], %w[X Y]])
    end
  end

  context "with transition labels" do
    let(:tree) do
      [
        { from: "A", to: "B", label: { label_text: "go [ready]" } },
        { from: "B", to: "C", label: { label_text: "plain" } },
        { from: "C", to: "D", label: { label_text: "   " } },
        { from: "D", to: "E" },
      ]
    end

    it "splits trigger and guard, and leaves them nil when absent" do
      expect(diagram.transitions.map { |t| [t.trigger, t.guard_condition] })
        .to eq([%w[go ready], ["plain", nil], [nil, nil], [nil, nil]])
    end
  end

  context "with composite states" do
    let(:tree) do
      [
        { keyword: "state", state_id: "Outer",
          state_label: { string: " Outer label " },
          composite: [{ from: "I1", to: "I2" }, "noise",
                      { state_id: "I3", description: "third" }] },
        { keyword: "state", state_id: "Hash",
          composite: { from: "H1", to: "H2" } },
        { keyword: "state", state_id: "Odd", composite: "text" },
        { keyword: "state", state_id: "Blank", state_label: "   " },
      ]
    end

    it "builds nested states from an array composite, keeping other parents" do
      expect(ids(diagram.states)).to eq(%w[Outer I1 I2 I3 Hash Odd Blank])
    end

    it "ignores composite data that is neither a hash nor an array" do
      expect(diagram.find_state("Odd").label).to eq("Odd")
    end

    it "labels with the trimmed alias, falling back to the id when blank",
       :aggregate_failures do
      expect(diagram.find_state("Outer").label).to eq("Outer label")
      expect(diagram.find_state("Blank").label).to eq("Blank")
    end

    it "records standalone descriptions on the state" do
      expect(diagram.find_state("I3").description).to eq("third")
    end
  end

  context "with declarations, markers, notes and separators" do
    let(:tree) do
      [
        { keyword: "state", state_id: "Plain", description: "desc" },
        { keyword: "state", state_id: "Plain", state_label: "Renamed" },
        { keyword: "state", state_id: "Fork",
          marker: { marker_type: "<<fork>>" } },
        { keyword: "state", state_id: "Fork",
          marker: { marker_type: "<<join>>" } },
        { note_keyword: "note" },
        { style_keyword: "classDef" },
        { concurrent_sep: "--" },
        { state_id: "Lone" },
        { unknown: true },
      ]
    end

    it "updates existing states, keeps the first special type, and drops notes",
       :aggregate_failures do
      expect(diagram.find_state("Plain").label).to eq("Renamed")
      expect(diagram.find_state("Plain").description).to eq("desc")
      expect(diagram.find_state("Fork").state_type).to eq("<<fork>>")
      expect(ids(diagram.states)).to eq(%w[Plain Fork Lone])
    end
  end

  describe "text extraction" do
    let(:tree) do
      [{ from: { dir_value: "LR" }, to: { label_text: "txt" } },
       { from: { other: "first" }, to: 5 }]
    end

    it "unwraps known single-key hashes, else first value or to_s" do
      pairs = diagram.transitions.map { |t| [t.from_id, t.to_id] }
      expect(pairs).to eq([%w[LR txt], %w[first 5]])
    end
  end

  describe "an end marker reached before any start" do
    let(:tree) { [{ from: "A", to: "[*]" }, { from: "[*]", to: "B" }] }

    it "creates the end state first and a separate start state later" do
      expect(diagram.states.map(&:state_type)).to eq(%w[end normal start
                                                        normal])
    end
  end
end
