# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::StateDiagramParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    it 'parses simple state diagram with two states' do
      source = "stateDiagram-v2\nIdle-->Active"
      diagram = parser.parse(source)

      expect(diagram).to be_a(Sirena::Diagram::StateDiagram)
      expect(diagram.states.length).to eq(2)
      expect(diagram.transitions.length).to eq(1)
    end

    it 'parses state diagram with start state' do
      source = "stateDiagram-v2\n[*]-->Idle"
      diagram = parser.parse(source)

      start_state = diagram.start_state
      expect(start_state).not_to be_nil
      expect(start_state.state_type).to eq('start')
      expect(diagram.transitions.length).to eq(1)
    end

    it 'parses state diagram with end state' do
      source = "stateDiagram-v2\nActive-->[*]"
      diagram = parser.parse(source)

      end_states = diagram.end_states
      expect(end_states.length).to eq(1)
      expect(end_states.first.state_type).to eq('end')
    end

    it 'parses complete state machine' do
      source = "stateDiagram-v2\n[*]-->Idle\nIdle-->Active\nActive-->[*]"
      diagram = parser.parse(source)

      expect(diagram.states.length).to eq(4)
      expect(diagram.transitions.length).to eq(3)
      expect(diagram.start_state).not_to be_nil
      expect(diagram.end_states.length).to eq(1)
    end

    it 'parses transition with trigger' do
      source = "stateDiagram-v2\nIdle-->Active: start"
      diagram = parser.parse(source)

      transition = diagram.transitions.first
      expect(transition.trigger).to eq('start')
      expect(transition.guard_condition).to be_nil
    end

    it 'parses transition with trigger and guard' do
      source = "stateDiagram-v2\nIdle-->Active: start [ready]"
      diagram = parser.parse(source)

      transition = diagram.transitions.first
      expect(transition.trigger).to eq('start')
      expect(transition.guard_condition).to eq('ready')
    end

    it 'parses choice state' do
      source = "stateDiagram-v2\nstate choice1 <<choice>>"
      diagram = parser.parse(source)

      choice = diagram.find_state('choice1')
      expect(choice).not_to be_nil
      expect(choice.state_type).to eq('choice')
    end

    it 'keeps alias syntax literal in a marker state id' do
      source = <<~MERMAID
        stateDiagram-v2
        state "X" as Y <<choice>>
        Y --> A
      MERMAID
      diagram = parser.parse(source)

      expect(diagram.states.map { |state| [state.id, state.state_type] }).to eq(
        [['"X" as Y', 'choice'], ['Y', 'normal'], ['A', 'normal']]
      )
      transitions = diagram.transitions.map do |transition|
        [transition.from_id, transition.to_id]
      end
      expect(transitions).to eq([%w[Y A]])
    end

    it 'keeps marker-like text inside a marker state id' do
      diagram = parser.parse(
        %(stateDiagram-v2\nstate "A <<choice>> B" <<fork>>\n)
      )

      expect(diagram.states.map { |state| [state.id, state.state_type] })
        .to eq([['"A <<choice>> B"', 'fork']])
    end

    it 'parses fork state' do
      source = "stateDiagram-v2\nstate fork1 <<fork>>"
      diagram = parser.parse(source)

      fork = diagram.find_state('fork1')
      expect(fork).not_to be_nil
      expect(fork.state_type).to eq('fork')
    end

    it 'parses join state' do
      source = "stateDiagram-v2\nstate join1 <<join>>"
      diagram = parser.parse(source)

      join = diagram.find_state('join1')
      expect(join).not_to be_nil
      expect(join.state_type).to eq('join')
    end

    it 'parses state with description' do
      source = "stateDiagram-v2\nstate Idle: System is idle"
      diagram = parser.parse(source)

      state = diagram.find_state('Idle')
      expect(state).not_to be_nil
      expect(state.description).to eq('System is idle')
    end

    it 'parses a direction statement' do
      source = "stateDiagram-v2\ndirection LR\nIdle-->Active"
      diagram = parser.parse(source)

      expect(diagram.direction).to eq('LR')
    end

    # mmdc 11.12.0 reads nothing on the keyword's line as a direction: it
    # draws `stateDiagram-v2 LR` as a state called LR.
    it 'reads a word after the keyword as a state, not a direction' do
      source = "stateDiagram-v2 LR\nIdle-->Active"
      diagram = parser.parse(source)

      expect(diagram.direction).to be_nil
      expect(diagram.states.map(&:id)).to include('LR')
    end

    it 'parses multiple transitions in sequence' do
      source = "stateDiagram-v2\nA-->B-->C"
      diagram = parser.parse(source)

      expect(diagram.states.length).to eq(3)
      expect(diagram.transitions.length).to eq(2)

      trans1 = diagram.transitions[0]
      expect(trans1.from_id).to eq('A')
      expect(trans1.to_id).to eq('B')

      trans2 = diagram.transitions[1]
      expect(trans2.from_id).to eq('B')
      expect(trans2.to_id).to eq('C')
    end

    it 'raises ParseError for invalid syntax' do
      source = 'invalid syntax'
      expect { parser.parse(source) }.to raise_error(
        Sirena::Parser::ParseError
      )
    end
  end

  # One example per corpus case the statement form was added for. Every
  # claim about mermaid below was measured against mmdc 11.12.0.
  describe 'mermaid corpus statement forms' do
    def corpus(name)
      parser.parse(File.read("spec/mermaid/#{name}"))
    end

    describe 'state "Label" as Id' do
      it 'names and labels a state (state_diagram/019)' do
        diagram = corpus(
          'state_diagram/019_parser_should_handle_state_definitions_' \
          'with_separation_of_id_18.mmd'
        )

        expect(diagram.find_state('NotShooting').label)
          .to eq('Not Shooting State')
        expect(diagram.find_state('Idle').label).to eq('Idle mode')
        expect(diagram.find_state('Configuring').label)
          .to eq('Configuring mode')
      end

      it 'labels a composite carrying a note (state_diagram/052)' do
        diagram = corpus(
          'state_diagram/052_parser_should_handle_notes_for_composite_' \
          'nested_states_51.mmd'
        )

        expect(diagram.find_state('NotShooting').label)
          .to eq('Not Shooting State')
        expect(diagram.transitions.map(&:to_id)).to include('NotShooting')
        expect(diagram.states.map(&:id))
          .to eq(%w[start_1 NotShooting Idle Configuring])
      end

      # mmdc refuses the reverse order: `state Idle as "Idle mode"` is a
      # parse error there.
      it 'refuses the alias with the label last' do
        source = %(stateDiagram-v2\nstate Idle as "Idle mode"\n)

        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError)
        # The accepted order belongs in the same example. Without it this
        # passes on origin/main, where the alias form does not parse at all.
        expect(
          parser.parse(%(stateDiagram-v2\nstate "Idle mode" as Idle\n))
            .find_state('Idle').label
        ).to eq('Idle mode')
      end

      # mmdc takes a double-quoted label only.
      it 'refuses a single-quoted alias label' do
        expect { parser.parse("stateDiagram-v2\nstate 'L' as N\n") }
          .to raise_error(Sirena::Parser::ParseError)
        expect(
          parser.parse(%(stateDiagram-v2\nstate "L" as N\n))
            .find_state('N').label
        ).to eq('L')
      end

      it 'refuses an empty alias label' do
        expect { parser.parse(%(stateDiagram-v2\nstate "" as N\n)) }
          .to raise_error(Sirena::Parser::ParseError)
        expect(
          parser.parse(%(stateDiagram-v2\nstate "x" as N\n))
            .find_state('N').label
        ).to eq('x')
      end

      # Mermaid accumulates aliases and descriptions as display text in source
      # order without changing the state's id.
      it 'keeps an alias label when a later line describes the state' do
        diagram = parser.parse(%(stateDiagram-v2\nstate "L" as A\nA : two\n))

        expect(diagram.find_state('A').label).to eq('L')
        expect(diagram.find_state('A').description).to eq('two')
        expect(diagram.find_state('A').descriptions).to eq(%w[L two])
      end

      it 'keeps an alias label when an earlier line described the state' do
        diagram = parser.parse(%(stateDiagram-v2\nA : two\nstate "L" as A\n))

        expect(diagram.find_state('A').label).to eq('L')
        expect(diagram.find_state('A').description).to eq('two')
        expect(diagram.find_state('A').descriptions).to eq(%w[two L])
      end

      it 'keeps a quoted alias id distinct from its unquoted spelling' do
        diagram = parser.parse(
          %(stateDiagram-v2\nstate "L" as "X"\nX --> A\n)
        )

        expect(diagram.states.map(&:id)).to eq(['"X"', 'X', 'A'])
        expect(diagram.find_state('"X"').label).to eq('L')
        expect(diagram.transitions.first.from_id).to eq('X')
      end
    end

    describe 'statement whitespace' do
      it 'accepts repeated spaces at Mermaid-flexible separators' do
        source = <<~MERMAID
          stateDiagram-v2
          direction  LR
          state  "Label"  as  A
          style  A  fill:red
          note  right of  A : attached
          note  "floating"  as  N
        MERMAID
        diagram = parser.parse(source)

        expect(diagram.direction).to eq('LR')
        expect(diagram.states.map(&:id)).to eq(['A'])
        expect(diagram.find_state('A').label).to eq('Label')

        # Mermaid's lexer is deliberately narrower between `right` and `of`.
        expect do
          parser.parse("stateDiagram-v2\nA\nnote right  of A : attached\n")
        end.to raise_error(Sirena::Parser::ParseError)

        marker_diagram = parser.parse(
          "stateDiagram-v2\nstate  A <<choice>>\n"
        )
        expect(marker_diagram.states.map { |state| [state.id, state.state_type] })
          .to eq([['A', 'choice']])
      end
    end

    describe 'id : description' do
      it 'describes a state, spaces around the colon (state_diagram/002)' do
        diagram = corpus(
          'state_diagram/002_parser_space_before_and_after_the_colon_1.mmd'
        )

        expect(diagram.find_state('namedState1').description)
          .to eq('Small State 1')
      end

      # The brace belongs to the description in the bare form and opens a
      # composite body in the keyword form: mmdc draws `A : text {` and
      # refuses `state A : text {`.
      it 'keeps a brace in a bare description' do
        diagram = parser.parse("stateDiagram-v2\nA : text {\n")

        expect(diagram.find_state('A').description).to eq('text {')
      end

      it 'refuses a brace in a state statement description' do
        expect { parser.parse("stateDiagram-v2\nstate A : text {\n") }
          .to raise_error(Sirena::Parser::ParseError)
        # mmdc draws `A : text {` as a state labelled `text {`, and refuses it
        # only after the `state` keyword. The bare form is the control.
        expect(parser.parse("stateDiagram-v2\nA : text {\n").states.length)
          .to eq(1)
      end

      it 'describes a state, no spaces (state_diagram/003)' do
        diagram = corpus(
          'state_diagram/003_parser_no_spaces_before_and_after_the_colon_2.mmd'
        )

        expect(diagram.find_state('namedState1').description)
          .to eq('Small State 1')
      end
    end

    describe 'note statements' do
      it 'reads a note block to its end note (state_diagram/026)' do
        diagram = corpus(
          'state_diagram/026_parser_should_handle_multiline_notes_with_' \
          'different_line_breaks_25.mmd'
        )

        expect(diagram.states.map(&:id)).to eq(['State1'])
      end

      it 'reads a single-line note' do
        diagram = parser.parse(
          "stateDiagram-v2\nState1\nnote right of State1 : hello\n"
        )

        expect(diagram.states.map(&:id)).to eq(['State1'])
      end

      # mmdc reads everything after a colon-less note as a note body, so it
      # refuses the file when no `end note` closes it.
      it 'refuses a colon-less note whose body runs to another statement' do
        expect { parser.parse("stateDiagram-v2\nA\nnote right of A\nbody\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'refuses a colon-less note that ends the file' do
        expect { parser.parse("stateDiagram-v2\nA\nnote right of A\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      # Only a whole line closes the block. mmdc keeps this one as text.
      it 'keeps an end note prefix inside a body line as note text' do
        diagram = parser.parse(
          "stateDiagram-v2\nA\nnote right of A\nend noteB\nend note\n"
        )

        expect(diagram.states.map(&:id)).to eq(['A'])
      end

      it 'refuses a body line ending in end note without a terminator line' do
        source = "stateDiagram-v2\nA\nnote right of A\nsay end note\n"

        expect { parser.parse(source) }
          .to raise_error(Sirena::Parser::ParseError)
        closed = "stateDiagram-v2\nA\nnote right of A\nsay end note\nend note\n"
        expect(parser.parse(closed).states.length).to eq(1)
      end

      # mmdc keeps a body line that ends in `;` or holds a `%%` comment.
      it 'keeps a semicolon and a comment marker inside a note body' do
        diagram = parser.parse(
          "stateDiagram-v2\nA\nnote right of A\nfoo;\n%% x\nend note\n"
        )

        expect(diagram.states.map(&:id)).to eq(['A'])
      end

      it 'accepts a note block with an empty body' do
        diagram = parser.parse(
          "stateDiagram-v2\nA\nnote right of A\nend note\n"
        )

        expect(diagram.states.map(&:id)).to eq(['A'])
      end

      # mmdc takes a non-empty double-quoted text only.
      it 'refuses a single-quoted floating note' do
        expect { parser.parse("stateDiagram-v2\nA\nnote 'f' as N1\n") }
          .to raise_error(Sirena::Parser::ParseError)
        expect(
          parser.parse(%(stateDiagram-v2\nA\nnote "f" as N1\n)).states.length
        ).to eq(1)
      end

      it 'refuses an empty floating note' do
        expect { parser.parse(%(stateDiagram-v2\nA\nnote "" as N1\n)) }
          .to raise_error(Sirena::Parser::ParseError)
        expect(
          parser.parse(%(stateDiagram-v2\nA\nnote "f" as N1\n)).states.length
        ).to eq(1)
      end

      # mmdc parses a floating note and draws nothing for it.
      it 'drops a floating note (state_diagram/027)' do
        diagram = corpus(
          'state_diagram/027_parser_should_handle_floating_notes_26.mmd'
        )

        expect(diagram.states.map(&:id)).to eq(['foo'])
        expect(diagram.find_state('foo').description).to eq('bar')
      end
    end

    describe 'style statements' do
      it 'drops a style over several targets (state_diagram/006)' do
        diagram = corpus(
          'state_diagram/006_parser_can_define_multiple_attributes_' \
          'separated_by_commas_5.mmd'
        )

        expect(diagram.states.map(&:id)).to eq(%w[id1 id2])
      end

      # mmdc takes a bare `style A` with no properties at all.
      it 'accepts a style with no properties' do
        diagram = parser.parse("stateDiagram-v2\nA\nstyle A\n")

        expect(diagram.states.map(&:id)).to eq(['A'])
      end

      # A `;` splits nothing here: mmdc draws the same picture either way.
      it 'keeps a semicolon inside the property list' do
        diagram = parser.parse(
          "stateDiagram-v2\nA\nB\nstyle A fill:red;stroke:blue\n"
        )

        expect(diagram.states.map(&:id)).to eq(%w[A B])
      end

      # mmdc renders `style note fill:red` even though it refuses `note`
      # as a state on its own.
      it 'takes a reserved name as a style target' do
        diagram = parser.parse("stateDiagram-v2\nA\nstyle note fill:red\n")

        expect(diagram.states.map(&:id)).to eq(['A'])
      end
    end

    describe 'direction statements' do
      it 'sets the direction (state/060)' do
        diagram = corpus('state/060_spec_mermaidapi_spec_59.mmd')

        expect(diagram.direction).to eq('LR')
        expect(diagram.find_state('direction')).to be_nil
      end

      # mmdc knows TB, BT, LR and RL here and nothing else: `direction TD`
      # draws two states called `direction` and `TD`.
      it 'refuses TD as a direction' do
        expect { parser.parse("stateDiagram-v2\ndirection TD\nA-->B\n") }
          .to raise_error(Sirena::Parser::ParseError)
        expect(parser.parse("stateDiagram-v2\ndirection TB\nA-->B\n").direction)
          .to eq('TB')
      end
    end

    describe 'state ids' do
      it 'takes a digits-only id (state/001)' do
        diagram = corpus(
          'state/001_rendering_statediagram-v2_spec_state_0.mmd'
        )

        expect(diagram.states.map(&:id)).to eq(%w[s2 s3 s4 55])
      end

      # mmdc lexes `note` and `style` wherever a statement or a transition
      # end may start, so it refuses these three and renders `notes`.
      it 'refuses a bare note as a state (state_diagram/031)' do
        expect do
          corpus(
            'state_diagram/031_parser_should_handle_floating_notes_30.mmd'
          )
        end.to raise_error(Sirena::Parser::ParseError)
      end

      it 'refuses note at a transition end' do
        expect { parser.parse("stateDiagram-v2\nA --> note\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'refuses style at a transition end' do
        expect { parser.parse("stateDiagram-v2\nA --> style\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'treats a bare state keyword as an empty statement' do
        diagram = parser.parse("stateDiagram-v2\nstate\n")

        expect(diagram.states).to be_empty
      end

      it 'refuses state at a transition end' do
        expect { parser.parse("stateDiagram-v2\nA --> state\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end

      it 'takes reserved names once a state statement claims the line' do
        diagram = parser.parse(
          "stateDiagram-v2\nstate note\nstate style\nstate state\n" \
          "notes\nstyles\n"
        )

        expect(diagram.states.map(&:id))
          .to eq(%w[note style state notes styles])
      end
    end

    describe 'a diagram with no statements' do
      it 'parses to an empty, valid diagram (state/055)' do
        diagram = corpus('state/055_spec_diagram-orchestration_spec_54.mmd')

        expect(diagram.states).to be_empty
        expect(diagram.valid?).to be true
      end
    end
  end
end
