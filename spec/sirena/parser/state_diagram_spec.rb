# frozen_string_literal: true

require "spec_helper"

module StateDiagramSpecHelpers
  def corpus(name)
    parser.parse(File.read(File.expand_path("../../mermaid/#{name}", __dir__)))
  end

  def concurrent_state_ids(diagram)
    regions = diagram.find_state("s2").children
    [diagram.states.map(&:id),
     regions.map { |region| region.children.map(&:id) }]
  end
end

RSpec.describe Sirena::Parser::StateDiagram do
  include StateDiagramSpecHelpers

  let(:parser) { described_class.new }

  context "when parsing simple state diagram with " \
          "two states", :aggregate_failures do
    let(:source) { "stateDiagram-v2\nIdle-->Active" }
    let(:diagram) { parser.parse(source) }

    it "retains diagram" do
      expect(diagram).to be_a(Sirena::Diagram::StateDiagram)
    end

    it "retains diagram.states.length" do
      expect(diagram.states.length).to eq(2)
    end

    it "retains diagram.transitions.length" do
      expect(diagram.transitions.length).to eq(1)
    end
  end

  context "when parsing state diagram with start " \
          "state", :aggregate_failures do
    let(:source) { "stateDiagram-v2\n[*]-->Idle" }
    let(:diagram) { parser.parse(source) }

    it "retains start_state" do
      start_state = diagram.start_state

      expect(start_state).not_to be_nil
    end

    it "retains start_state.state_type" do
      start_state = diagram.start_state

      expect(start_state.state_type).to eq("start")
    end

    it "retains diagram.transitions.length" do
      expect(diagram.transitions.length).to eq(1)
    end
  end

  context "when parsing state diagram with end state", :aggregate_failures do
    let(:source) { "stateDiagram-v2\nActive-->[*]" }
    let(:diagram) { parser.parse(source) }

    it "retains end_states.length" do
      end_states = diagram.end_states

      expect(end_states.length).to eq(1)
    end

    it "retains end_states.first.state_type" do
      end_states = diagram.end_states

      expect(end_states.first.state_type).to eq("end")
    end
  end

  context "when parsing complete state machine", :aggregate_failures do
    let(:source) do
      "stateDiagram-v2\n[*]-->Idle\nIdle-->Active\nActive-->[*]"
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.states.length" do
      expect(diagram.states.length).to eq(4)
    end

    it "retains diagram.transitions.length" do
      expect(diagram.transitions.length).to eq(3)
    end

    it "retains diagram.start_state" do
      expect(diagram.start_state).not_to be_nil
    end

    it "retains diagram.end_states.length" do
      expect(diagram.end_states.length).to eq(1)
    end
  end

  context "when parsing transition with trigger", :aggregate_failures do
    let(:source) { "stateDiagram-v2\nIdle-->Active: start" }
    let(:diagram) { parser.parse(source) }

    it "retains transition.trigger" do
      transition = diagram.transitions.first

      expect(transition.trigger).to eq("start")
    end

    it "retains transition.guard_condition" do
      transition = diagram.transitions.first

      expect(transition.guard_condition).to be_nil
    end
  end

  context "when parsing transition with trigger and " \
          "guard", :aggregate_failures do
    let(:source) { "stateDiagram-v2\nIdle-->Active: start [ready]" }
    let(:diagram) { parser.parse(source) }

    it "retains transition.trigger" do
      transition = diagram.transitions.first

      expect(transition.trigger).to eq("start")
    end

    it "retains transition.guard_condition" do
      transition = diagram.transitions.first

      expect(transition.guard_condition).to eq("ready")
    end
  end

  context "when parsing choice state", :aggregate_failures do
    let(:source) { "stateDiagram-v2\nstate choice1 <<choice>>" }
    let(:diagram) { parser.parse(source) }

    it "retains choice" do
      choice = diagram.find_state("choice1")

      expect(choice).not_to be_nil
    end

    it "retains choice.state_type" do
      choice = diagram.find_state("choice1")

      expect(choice.state_type).to eq("choice")
    end
  end

  context "when keeps alias syntax literal in a " \
          "marker state id", :aggregate_failures do
    let(:source) do
      <<~MERMAID
        stateDiagram-v2
        state "X" as Y <<choice>>
        Y --> A
      MERMAID
    end
    let(:diagram) { parser.parse(source) }

    it "retains diagram.states.map state state.id state.state_type" do
      expect(diagram.states.map { |state| [state.id, state.state_type] }).to eq(
        [['"X" as Y', "choice"], ["Y", "normal"], ["A", "normal"]],
      )
    end

    it "retains transitions" do
      transitions = diagram.transitions.map do |transition|
        [transition.from_id, transition.to_id]
      end

      expect(transitions).to eq([%w[Y A]])
    end
  end

  context "when keeps marker-like text inside a " \
          "marker state id", :aggregate_failures do
    let(:diagram) do
      parser.parse(
        %(stateDiagram-v2\nstate "A <<choice>> B" <<fork>>\n),
      )
    end

    it "retains diagram.states.map state state.id state.state_type" do
      expect(diagram.states.map { |state| [state.id, state.state_type] })
        .to eq([['"A <<choice>> B"', "fork"]])
    end
  end

  context "when parsing fork state", :aggregate_failures do
    let(:source) { "stateDiagram-v2\nstate fork1 <<fork>>" }
    let(:diagram) { parser.parse(source) }

    it "retains fork" do
      fork = diagram.find_state("fork1")

      expect(fork).not_to be_nil
    end

    it "retains fork.state_type" do
      fork = diagram.find_state("fork1")

      expect(fork.state_type).to eq("fork")
    end
  end

  context "when parsing join state", :aggregate_failures do
    let(:source) { "stateDiagram-v2\nstate join1 <<join>>" }
    let(:diagram) { parser.parse(source) }

    it "retains join" do
      join = diagram.find_state("join1")

      expect(join).not_to be_nil
    end

    it "retains join.state_type" do
      join = diagram.find_state("join1")

      expect(join.state_type).to eq("join")
    end
  end

  context "when parsing state with description", :aggregate_failures do
    let(:source) { "stateDiagram-v2\nstate Idle: System is idle" }
    let(:diagram) { parser.parse(source) }

    it "retains state" do
      state = diagram.find_state("Idle")

      expect(state).not_to be_nil
    end

    it "retains state.description" do
      state = diagram.find_state("Idle")

      expect(state.description).to eq("System is idle")
    end
  end

  it "parses a direction statement", :aggregate_failures do
    source = "stateDiagram-v2\ndirection LR\nIdle-->Active"
    diagram = parser.parse(source)

    expect(diagram.direction).to eq("LR")
  end

  # mmdc 11.12.0 reads nothing on the keyword's line as a direction: it
  # draws `stateDiagram-v2 LR` as a state called LR.
  context "when reads a word after the keyword as a " \
          "state, not a direction", :aggregate_failures do
    let(:source) { "stateDiagram-v2 LR\nIdle-->Active" }
    let(:diagram) { parser.parse(source) }

    it "retains diagram.direction" do
      expect(diagram.direction).to be_nil
    end

    it "retains diagram.states.map id" do
      expect(diagram.states.map(&:id)).to include("LR")
    end
  end

  context "when parsing multiple transitions in " \
          "sequence", :aggregate_failures do
    let(:source) { "stateDiagram-v2\nA-->B-->C" }
    let(:diagram) { parser.parse(source) }

    it "retains diagram.states.length" do
      expect(diagram.states.length).to eq(3)
    end

    it "retains diagram.transitions.length" do
      expect(diagram.transitions.length).to eq(2)
    end

    it "retains trans1.from_id" do
      trans1 = diagram.transitions[0]

      expect(trans1.from_id).to eq("A")
    end

    it "retains trans1.to_id" do
      trans1 = diagram.transitions[0]

      expect(trans1.to_id).to eq("B")
    end

    it "retains trans2.from_id" do
      trans2 = diagram.transitions[1]

      expect(trans2.from_id).to eq("B")
    end

    it "retains trans2.to_id" do
      trans2 = diagram.transitions[1]

      expect(trans2.to_id).to eq("C")
    end
  end

  it "raises ParseError for invalid syntax", :aggregate_failures do
    source = "invalid syntax"
    expect { parser.parse(source) }.to raise_error(
      Sirena::Parser::ParseError,
    )
  end

  # One example per corpus case the statement form was added for. Every
  # claim about mermaid below was measured against mmdc 11.12.0.
  describe 'state "Label" as Id', :aggregate_failures do
    describe "names and labels a state (statediagram_v2_spec-2d12b6d7)" do
      let(:diagram) do
        corpus(
          "state_diagram/statediagram_v2_spec-2d12b6d7.mmd",
        )
      end

      before do
        diagram
      end

      it "preserves property 1" do
        expect(diagram.find_state("NotShooting").label)
          .to eq("Not Shooting State")
      end

      it "preserves property 2" do
        expect(diagram.find_state("Idle").label).to eq("Idle mode")
      end

      it "preserves property 3" do
        expect(diagram.find_state("Configuring").label)
          .to eq("Configuring mode")
      end
    end

    describe "labels a composite carrying a note " \
             "(statediagram_v2_spec-3249fd2d)" do
      let(:diagram) do
        corpus(
          "state_diagram/statediagram_v2_spec-3249fd2d.mmd",
        )
      end

      before do
        diagram
      end

      it "preserves property 1" do
        expect(diagram.find_state("NotShooting").label)
          .to eq("Not Shooting State")
      end

      it "preserves property 2" do
        expect(diagram.transitions.map(&:to_id)).to include("NotShooting")
      end

      it "preserves property 3" do
        expect([diagram.states.map(&:id),
                diagram.find_state("NotShooting").children.map(&:id)])
          .to eq([%w[start_1 NotShooting], %w[Idle Configuring start_2]])
      end
    end

    # mmdc refuses the reverse order: `state Idle as "Idle mode"` is a
    # parse error there.
    context "when refusing the alias with the label last" do
      let(:source) { %(stateDiagram-v2\nstate Idle as "Idle mode"\n) }

      it "rejects the invalid source" do
        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "retains label" do
        expect(
          parser.parse(%(stateDiagram-v2\nstate "Idle mode" as Idle\n))
            .find_state("Idle").label,
        ).to eq("Idle mode")
      end
    end

    # mmdc takes a double-quoted label only.
    context "when refusing a single-quoted alias label" do
      it "rejects the invalid source" do
        expect { parser.parse("stateDiagram-v2\nstate 'L' as N\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "retains label" do
        expect(
          parser.parse(%(stateDiagram-v2\nstate "L" as N\n))
            .find_state("N").label,
        ).to eq("L")
      end
    end

    context "when refusing an empty alias label" do
      it "rejects the invalid source" do
        expect { parser.parse(%(stateDiagram-v2\nstate "" as N\n)) }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "retains label" do
        expect(
          parser.parse(%(stateDiagram-v2\nstate "x" as N\n))
            .find_state("N").label,
        ).to eq("x")
      end
    end

    # Mermaid accumulates aliases and descriptions as display text in source
    # order without changing the state's id.
    context "when keeps an alias label when a later line describes the " \
            "state" do
      let(:diagram) do
        parser.parse(%(stateDiagram-v2\nstate "L" as A\nA : two\n))
      end

      it "retains diagram.find_state A .label" do
        expect(diagram.find_state("A").label).to eq("L")
      end

      it "retains diagram.find_state A .description" do
        expect(diagram.find_state("A").description).to eq("two")
      end

      it "retains diagram.find_state A .descriptions" do
        expect(diagram.find_state("A").descriptions).to eq(%w[L two])
      end
    end

    context "when keeps an alias label when an earlier line described " \
            "the state" do
      let(:diagram) do
        parser.parse(%(stateDiagram-v2\nA : two\nstate "L" as A\n))
      end

      it "retains diagram.find_state A .label" do
        expect(diagram.find_state("A").label).to eq("L")
      end

      it "retains diagram.find_state A .description" do
        expect(diagram.find_state("A").description).to eq("two")
      end

      it "retains diagram.find_state A .descriptions" do
        expect(diagram.find_state("A").descriptions).to eq(%w[two L])
      end
    end

    context "when keeps a quoted alias id distinct from its unquoted " \
            "spelling" do
      let(:diagram) do
        parser.parse(
          %(stateDiagram-v2\nstate "L" as "X"\nX --> A\n),
        )
      end

      it "retains diagram.states.map id" do
        expect(diagram.states.map(&:id)).to eq(['"X"', "X", "A"])
      end

      it "retains diagram.find_state X .label" do
        expect(diagram.find_state('"X"').label).to eq("L")
      end

      it "retains diagram.transitions.first.from_id" do
        expect(diagram.transitions.first.from_id).to eq("X")
      end
    end
  end

  describe "statement whitespace", :aggregate_failures do
    context "when accepts repeated spaces at Mermaid-flexible " \
            "separators" do
      let(:source) do
        <<~MERMAID
          stateDiagram-v2
          direction  LR
          state  "Label"  as  A
          style  A  fill:red
          note  right of  A : attached
          note  "floating"  as  N
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      let(:marker_states) do
        marker_diagram = parser.parse("stateDiagram-v2\nstate  A <<choice>>\n")
        marker_diagram.states.map { |state| [state.id, state.state_type] }
      end

      it "retains diagram.direction" do
        expect(diagram.direction).to eq("LR")
      end

      it "retains diagram.states.map id" do
        expect(diagram.states.map(&:id)).to eq(["A"])
      end

      it "retains diagram.find_state A .label" do
        expect(diagram.find_state("A").label).to eq("Label")
      end

      it "rejects the invalid source" do
        expect do
          parser.parse("stateDiagram-v2\nA\nnote right  of A : attached\n")
        end.to raise_error(Sirena::Parser::ParseError)
      end

      it "retains the spaced marker's id and state type" do
        expect(marker_states).to eq([["A", "choice"]])
      end
    end
  end

  describe "id : description", :aggregate_failures do
    it "describes a state, spaced colon (state_parser_spec-5ace89b8)" do
      diagram = corpus(
        "state_diagram/state_parser_spec-5ace89b8.mmd",
      )

      expect(diagram.find_state("namedState1").description)
        .to eq("Small State 1")
    end

    # The brace belongs to the description in the bare form and opens a
    # composite body in the keyword form: mmdc draws `A : text {` and
    # refuses `state A : text {`.
    it "keeps a brace in a bare description" do
      diagram = parser.parse("stateDiagram-v2\nA : text {\n")

      expect(diagram.find_state("A").description).to eq("text {")
    end

    context "when refusing a brace in a state statement description" do
      it "rejects the invalid source" do
        expect { parser.parse("stateDiagram-v2\nstate A : text {\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "retains parser.parse stateDiagram v2 nA text n .states.length" do
        expect(parser.parse("stateDiagram-v2\nA : text {\n").states.length)
          .to eq(1)
      end
    end

    it "describes a state, no spaces (state_parser_spec-4f6d8252)" do
      diagram = corpus(
        "state_diagram/state_parser_spec-4f6d8252.mmd",
      )

      expect(diagram.find_state("namedState1").description)
        .to eq("Small State 1")
    end
  end

  describe "note statements", :aggregate_failures do
    it "reads a note block to its end note (statediagram_v2_spec-6aad18a9)" do
      diagram = corpus(
        "state_diagram/statediagram_v2_spec-6aad18a9.mmd",
      )

      expect(diagram.states.map(&:id)).to eq(["State1"])
    end

    # A REGRESSION GUARD, not a proof of new behaviour. This parses
    # identically on origin/main; it is here because the note grammar was
    # rewritten around it and this is the shape that must not break.
    # mutation-check reports it STAYED GREEN for exactly that reason.
    it "reads a single-line note" do
      diagram = parser.parse(
        "stateDiagram-v2\nState1\nnote right of State1 : hello\n",
      )

      expect(diagram.states.map(&:id)).to eq(["State1"])
    end

    # mmdc reads everything after a colon-less note as a note body, so it
    # refuses the file when no `end note` closes it.
    it "refuses a colon-less note whose body runs to another statement" do
      expect { parser.parse("stateDiagram-v2\nA\nnote right of A\nbody\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "refuses a colon-less note that ends the file" do
      expect { parser.parse("stateDiagram-v2\nA\nnote right of A\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    # Only a whole line closes the block. mmdc keeps this one as text.
    it "keeps an end note prefix inside a body line as note text" do
      diagram = parser.parse(
        "stateDiagram-v2\nA\nnote right of A\nend noteB\nend note\n",
      )

      expect(diagram.states.map(&:id)).to eq(["A"])
    end

    context "when refusing a body line ending in end note without a " \
            "terminator line" do
      let(:source) { "stateDiagram-v2\nA\nnote right of A\nsay end note\n" }

      it "rejects the invalid source" do
        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "retains parser.parse closed .states.length" do
        closed = "stateDiagram-v2\nA\nnote right of A\nsay end note\nend note\n"

        expect(parser.parse(closed).states.length).to eq(1)
      end
    end

    # mmdc keeps a body line that ends in `;` or holds a `%%` comment.
    it "keeps a semicolon and a comment marker inside a note body" do
      diagram = parser.parse(
        "stateDiagram-v2\nA\nnote right of A\nfoo;\n%% x\nend note\n",
      )

      expect(diagram.states.map(&:id)).to eq(["A"])
    end

    it "accepts a note block with an empty body" do
      diagram = parser.parse(
        "stateDiagram-v2\nA\nnote right of A\nend note\n",
      )

      expect(diagram.states.map(&:id)).to eq(["A"])
    end

    # mmdc takes a non-empty double-quoted text only.
    context "when refusing a single-quoted floating note" do
      it "rejects the invalid source" do
        expect { parser.parse("stateDiagram-v2\nA\nnote 'f' as N1\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "retains length" do
        expect(
          parser.parse(%(stateDiagram-v2\nA\nnote "f" as N1\n)).states.length,
        ).to eq(1)
      end
    end

    context "when refusing an empty floating note" do
      it "rejects the invalid source" do
        expect { parser.parse(%(stateDiagram-v2\nA\nnote "" as N1\n)) }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "retains length" do
        expect(
          parser.parse(%(stateDiagram-v2\nA\nnote "f" as N1\n)).states.length,
        ).to eq(1)
      end
    end

    # mmdc parses a floating note and draws nothing for it.
    it "drops a floating note (statediagram_v2_spec-7f54c592)" do
      diagram = corpus(
        "state_diagram/statediagram_v2_spec-7f54c592.mmd",
      )

      expect(diagram.states.map(&:id)).to eq(["foo"])
      expect(diagram.find_state("foo").description).to eq("bar")
    end
  end

  describe "style statements", :aggregate_failures do
    it "drops a style over several targets (state_style_spec-c53cfe2e)" do
      diagram = corpus(
        "state_diagram/state_style_spec-c53cfe2e.mmd",
      )

      expect(diagram.states.map(&:id)).to eq(%w[id1 id2])
    end

    # mmdc takes a bare `style A` with no properties at all.
    it "accepts a style with no properties" do
      diagram = parser.parse("stateDiagram-v2\nA\nstyle A\n")

      expect(diagram.states.map(&:id)).to eq(["A"])
    end

    # A `;` splits nothing here: mmdc draws the same picture either way.
    it "keeps a semicolon inside the property list" do
      diagram = parser.parse(
        "stateDiagram-v2\nA\nB\nstyle A fill:red;stroke:blue\n",
      )

      expect(diagram.states.map(&:id)).to eq(%w[A B])
    end

    # mmdc renders `style note fill:red` even though it refuses `note`
    # as a state on its own.
    it "takes a reserved name as a style target" do
      diagram = parser.parse("stateDiagram-v2\nA\nstyle note fill:red\n")

      expect(diagram.states.map(&:id)).to eq(["A"])
    end
  end

  describe "direction statements", :aggregate_failures do
    it "sets the direction (state_diagram/mermaidapi_spec-c352a65c)" do
      diagram = corpus("state_diagram/mermaidapi_spec-c352a65c.mmd")

      expect(diagram.direction).to eq("LR")
      expect(diagram.find_state("direction")).to be_nil
    end

    # mmdc knows TB, BT, LR and RL here and nothing else: `direction TD`
    # draws two states called `direction` and `TD`.
    context "when refusing TD as a direction" do
      it "rejects the invalid source" do
        expect { parser.parse("stateDiagram-v2\ndirection TD\nA-->B\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it "retains direction" do
        expect(parser.parse("stateDiagram-v2\ndirection TB\nA-->B\n").direction)
          .to eq("TB")
      end
    end
  end

  describe "state ids", :aggregate_failures do
    it "takes a digits-only id (statediagram_v2_spec-c351b77a)" do
      diagram = corpus(
        "state_diagram/statediagram_v2_spec-c351b77a.mmd",
      )

      expect(concurrent_state_ids(diagram))
        .to eq([%w[s2], [%w[s3], %w[s4], %w[55]]])
    end

    # mmdc lexes `note` and `style` wherever a statement or a transition
    # end may start, so it refuses these three and renders `notes`.
    it "refuses a bare note as a state (statediagram_v2_spec-649d05f6)" do
      expect do
        corpus(
          "state_diagram/statediagram_v2_spec-649d05f6.mmd",
        )
      end.to raise_error(Sirena::Parser::ParseError)
    end

    it "refuses note at a transition end" do
      expect { parser.parse("stateDiagram-v2\nA --> note\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "refuses style at a transition end" do
      expect { parser.parse("stateDiagram-v2\nA --> style\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    it "treats a bare state keyword as an empty statement" do
      diagram = parser.parse("stateDiagram-v2\nstate\n")

      expect(diagram.states).to be_empty
    end

    it "refuses state at a transition end" do
      expect { parser.parse("stateDiagram-v2\nA --> state\n") }
        .to raise_error(Sirena::Parser::ParseError)
    end

    # The refusal belongs in the same example as the acceptance. Asserting
    # only that `state note` parses passes on origin/main too, where a
    # reserved word is an ordinary id everywhere — so it could not tell
    # "the keyword guard lets a claimed line through" from "there is no
    # guard at all". The transition form is what pins it.
    context "when takes reserved names once a state statement claims " \
            "the line" do
      let(:diagram) do
        parser.parse(
          "stateDiagram-v2\nstate note\nstate style\nstate state\n" \
          "notes\nstyles\n",
        )
      end

      it "retains diagram.states.map id" do
        expect(diagram.states.map(&:id))
          .to eq(%w[note style state notes styles])
      end

      it "rejects the invalid source" do
        expect { parser.parse("stateDiagram-v2\nA --> note\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  describe "a diagram with no statements", :aggregate_failures do
    it "parses to an empty diagram (diagram_orchestration_spec-367b369a)" do
      diagram = corpus(
        "state_diagram/diagram_orchestration_spec-367b369a.mmd",
      )

      expect(diagram.states).to be_empty
      expect(diagram.valid?).to be true
    end
  end

  describe "#parse a later declaration of a labelled state" do
    let(:states) do
      source = "stateDiagram-v2\n  state \"Long\" as s1\n  state s1\n"
      described_class.new.parse(source).states.to_h { [_1.id, _1.label] }
    end

    it "keeps the label the state was declared with" do
      expect(states["s1"]).to eq("Long")
    end
  end
end
