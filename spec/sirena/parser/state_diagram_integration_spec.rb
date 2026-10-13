# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "yaml"

module StateDiagramIntegrationSpecHelpers
  def rendered_state(source, state_id)
    document = REXML::Document.new(Sirena::Engine.new.render(source))
    REXML::XPath.first(document, "//*[@id='state-#{state_id}']")
  end

  def state_groups(source, state_id)
    document = REXML::Document.new(Sirena::Engine.new.render(source))
    REXML::XPath.match(document, "//*[@id='state-#{state_id}']")
  end

  def child_texts(group)
    REXML::XPath.match(group, "text").map(&:text)
  end

  def rendered_texts(engine, source)
    document = REXML::Document.new(engine.render(source))
    REXML::XPath.match(document, "//text").map(&:text)
  end

  def parse_failure(engine, source)
    engine.render(source)
    nil
  rescue Sirena::Parser::ParseError => e
    e
  end

  def shape_counts(group)
    [REXML::XPath.match(group, "rect").length,
     REXML::XPath.match(group, "polygon").length]
  end

  def header_line_direction_sources
    ["stateDiagram-v2direction LR\nA --> B\n",
     "stateDiagram-v2 direction LR\nA --> B\n",
     "stateDiagram-v2\tdirection LR\nA --> B\n"]
  end

  def parse_state(source)
    Sirena::Parser::StateDiagram.new.parse(source)
  end
end

# The oracle-valid case list for 'the oracle-valid corpus' describe block
# below, generated at describe-body level to build one example per case.
module StateDiagramOracleCases
  module_function

  def oracle_valid_cases
    mermaid_dir = SpecSupport::RepositoryPaths.path("spec/mermaid")
    verdicts = YAML.load_file(File.join(mermaid_dir, "corpus-verdicts.yml"))
      .to_h { |row| [row["case"], row["verdict"]] }

    %w[state state_diagram].flat_map do |type|
      valid_paths(mermaid_dir, type, verdicts)
    end.sort
  end

  def valid_paths(mermaid_dir, type, verdicts)
    Dir.glob(File.join(mermaid_dir, type, "*.mmd")).select do |path|
      verdicts[path.delete_prefix("#{mermaid_dir}/")] == "valid"
    end
  end
end

RSpec.describe Sirena::Parser::StateDiagram, :aggregate_failures do
  include StateDiagramIntegrationSpecHelpers

  describe "complete state diagram pipeline" do
    let(:diagram) { parse_state(source) }
    let(:transform) { Sirena::Layout::StateDiagram.new }
    let(:scene) { transform.to_graph(diagram) }
    let(:svg) { Sirena::Renderer::StateDiagram.new.render(scene) }

    context "with a simple state diagram" do
      let(:source) { "stateDiagram-v2\nIdle-->Active" }

      it "parses a valid StateDiagram" do
        expect(diagram).to be_a(Sirena::Diagram::StateDiagram)
        expect(diagram.valid?).to be true
      end

      it "transforms to a Scene with both states and the edge" do
        expect(scene).to be_a(Sirena::Layout::StateDiagram::Scene)
        expect(scene.children.length).to eq(2)
        expect(scene.edges.length).to eq(1)
      end

      it "renders a non-empty SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
        expect(svg.children).not_to be_empty
      end

      it "runs the temporary Grid while the state layout builds its Scene" do
        allow(Sirena::Layout::Grid).to receive(:apply).and_call_original
        scene
        expect(Sirena::Layout::Grid).to have_received(:apply)
          .once.with(an_instance_of(Hash))
      end
    end

    context "with a complete state machine with start and end" do
      let(:source) do
        <<~MERMAID
          stateDiagram-v2
          [*]-->Idle
          Idle-->Active: start
          Active-->[*]
        MERMAID
      end

      it "parses the states, start and end" do
        expect(diagram.states.length).to eq(4)
        expect(diagram.start_state).not_to be_nil
        expect(diagram.end_states.length).to eq(1)
      end

      it "parses the transitions" do
        expect(diagram.transitions.length).to eq(3)
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with special state types" do
      let(:source) do
        <<~MERMAID
          stateDiagram-v2
          state choice1 <<choice>>
          state fork1 <<fork>>
          state join1 <<join>>
          Idle-->choice1
          choice1-->Active
        MERMAID
      end

      it "parses the choice state" do
        expect(diagram.choice_states.length).to eq(1)
      end

      it "parses the fork and join states" do
        expect(diagram.find_state("fork1")).not_to be_nil
        expect(diagram.find_state("join1")).not_to be_nil
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with a transition with a trigger and guard" do
      let(:source) { "stateDiagram-v2\nIdle-->Active: start [ready]" }

      it "parses the trigger and guard" do
        transition = diagram.transitions.first

        expect(transition.trigger).to eq("start")
        expect(transition.guard_condition).to eq("ready")
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with a left-to-right direction" do
      let(:source) { "stateDiagram-v2\ndirection LR\nIdle-->Active" }

      it "parses the direction" do
        expect(diagram.direction).to eq("LR")
      end

      it "lays out to the right" do
        graph = transform.send(:build_graph, diagram)

        expect(graph[:layoutOptions]["elk.direction"]).to eq("RIGHT")
      end
    end
  end

  describe "one described state with an established type" do
    [
      ["stateDiagram-v2\nstate C <<choice>>\n" \
       "C : FIRST\nC : SECOND\n", "choice"],
      ["stateDiagram-v2\nC : FIRST\nstate C <<choice>>\n" \
       "C : SECOND\n", "normal"],
    ].each do |text, expected_type|
      context "with #{text.inspect}" do
        let(:states) do
          parse_state(text).states.select { |state| state.id == "C" }
        end
        let(:groups) { state_groups(text, "C") }

        it "keeps one model state of the first established type" do
          expect(states.length).to eq(1)
          expect(states.first.state_type).to eq(expected_type)
        end

        it "keeps the last description and every description" do
          expect(states.first.description).to eq("SECOND")
          expect(states.first.descriptions).to eq(%w[FIRST SECOND])
        end

        it "renders one group drawn as a rectangle" do
          expect(groups.length).to eq(1)
          expect(REXML::XPath.match(groups.first, "rect").length).to eq(1)
          expect(REXML::XPath.match(groups.first, "polygon")).to be_empty
        end

        it "renders both descriptions as text" do
          expect(child_texts(groups.first)).to eq(%w[FIRST SECOND])
        end
      end
    end
  end

  describe "direction statements" do
    let(:engine) { Sirena::Engine.new }
    let(:newline_form) { "stateDiagram-v2\ndirection LR\nA --> B\n" }

    it "requires direction statements to start below the header" do
      expect { engine.render("stateDiagram-v2 direction LR") }
        .to raise_error(Sirena::Parser::ParseError, /Parse error/)
      expect(rendered_texts(engine, newline_form)).to eq(%w[A B])
    end

    # mmdc 11.12.0 exits 1 with no output on every separator width, including
    # none at all: `stateDiagram-v2direction LR` is not a diagram. The first
    # guard here required one space, so the zero-space form walked past it.
    # The positive control belongs in THIS example, not a neighbouring one.
    # Asserting only the refusals passes on origin/main, where `direction` is
    # not supported at all and every form raises — so the example could not tell
    # "the guard fired" from "nothing parses". Rendering the newline form here
    # is what makes it fail without the feature.
    it "refuses a direction on the header line at any separator width" do
      failures = header_line_direction_sources
        .map { |source| parse_failure(engine, source) }

      expect(failures).to all(have_attributes(message: /Parse error/))
      expect(rendered_texts(engine, newline_form)).to eq(%w[A B])
    end
  end

  describe "marker states that carry display text" do
    # An alias is stored in `descriptions`, never in the scalar `description`,
    # so it coerces either established type to a rectangle at render time.
    [
      ["stateDiagram-v2\nstate C <<choice>>\nstate \"Label\" as C\n", "choice"],
      ["stateDiagram-v2\nstate \"Label\" as C\nstate C <<choice>>\n", "normal"],
    ].each do |text, expected_type|
      context "with an aliased state #{text.inspect}" do
        it "preserves the first established type" do
          expect(parse_state(text).find_state("C").state_type)
            .to eq(expected_type)
        end

        it "draws it as a rectangle" do
          svg = Sirena::Engine.new.render(text)

          expect([svg.scan("<polygon").size, svg.scan("<rect").size])
            .to eq([0, 1])
        end
      end
    end

    # The guard above must not reach the scalar label. Keying the shape on the
    # state id would turn every otherwise-unlabelled marker into a rectangle.
    #
    # Scoped to state-C's own group rather than counted across the whole
    # document: the `C --> A` edge now draws a real arrowhead as a second,
    # sibling `<polygon>` (Svg::Arrowhead — SVG Tiny 1.2 has no `<marker>` to
    # reference, so the head is drawn inline; before that class existed no
    # arrowhead was drawn anywhere in the gem). A page-wide count would fail
    # on that unrelated polygon instead of testing what this example names.
    it "keeps a marker without display text as an unlabelled polygon" do
      choice = rendered_state("stateDiagram-v2\nstate C <<choice>>\nC --> A\n",
                              "C")

      expect(REXML::XPath.match(choice, "polygon").size).to eq(1)
      expect(REXML::XPath.match(choice, "rect")).to be_empty
      expect(child_texts(choice)).to eq([])
    end

    [
      ["stateDiagram-v2\nC --> A\nstate C <<choice>>\n", [1, 0]],
      ["stateDiagram-v2\nstate C <<choice>>\nC --> A\n", [0, 1]],
      ["stateDiagram-v2\nstate C <<fork>>\nstate C <<choice>>\n", [1, 0]],
      ["stateDiagram-v2\nstate C <<choice>>\nstate C <<fork>>\n", [0, 1]],
    ].each do |text, expected_shapes|
      context "with the type declarations in #{text.inspect}" do
        let(:groups) { state_groups(text, "C") }

        # Count the groups, do not just inspect the first. Substituting the
        # origin/main `add_special_state` at runtime left every shape
        # assertion here GREEN while three of these four sources built two
        # model states and emitted two duplicate `state-C` groups. Reading
        # only the first group cannot see a duplicate, which is the whole
        # defect.
        it "emits exactly one group" do
          expect(groups.length).to eq(1)
        end

        it "renders the first established state type" do
          expect(shape_counts(groups.first)).to eq(expected_shapes)
        end
      end
    end

    # mmdc 11.12.0 refuses each of these as a transition target, in any case:
    # one source per word, every one exits 1 with no output. `classroom` and
    # `notes` render, so the guard must not swallow a longer identifier.
    %w[class classDef click href scale default note state style
       Class CLASS clAsS NOTE Default classdef].each do |word|
      it "refuses #{word} as a state id" do
        expect { Sirena::Engine.new.render("stateDiagram-v2\nA --> #{word}\n") }
          .to raise_error(Sirena::Parser::ParseError)
      end
    end

    %w[classroom notes styles stateful].each do |word|
      it "accepts #{word} as a state id" do
        expect { Sirena::Engine.new.render("stateDiagram-v2\nA --> #{word}\n") }
          .not_to raise_error
      end
    end

    it "trims alias labels" do
      labelled = rendered_state(
        "stateDiagram-v2\nstate \"  Label  \" as C\n",
        "C",
      )

      expect(child_texts(labelled)).to eq(["Label"])
    end

    it "ignores a whitespace-only alias on a choice state" do
      source = "stateDiagram-v2\nstate C <<choice>>\nstate \"   \" as C\n"
      choice = rendered_state(source, "C")

      expect(shape_counts(choice)).to eq([0, 1])
      expect(child_texts(choice)).to eq([])
    end
  end

  describe "state text syntax" do
    it "rejects escaped alias quotes" do
      expect do
        Sirena::Engine.new.render("stateDiagram-v2\nstate \"A\\\"B\" as X\n")
      end.to raise_error(Sirena::Parser::ParseError, /Parse error/)
    end

    it "renders an ordinary alias" do
      group = rendered_state("stateDiagram-v2\nstate \"AB\" as X\n", "X")

      expect(child_texts(group)).to eq(["AB"])
    end

    [
      ["stateDiagram-v2\nA :   ", ["A"]],
      ["stateDiagram-v2\nA : %% comment\n", ["%% comment"]],
      ["stateDiagram-v2\nA : Text %% comment\n", ["Text %% comment"]],
    ].each do |text, expected_text|
      it "renders a bare description through the line ending of " \
         "#{text.inspect}" do
        expect(child_texts(rendered_state(text, "A"))).to eq(expected_text)
      end
    end

    ["stateDiagram-v2\nA :\n", "stateDiagram-v2\nA :"].each do |text|
      it "requires content or horizontal whitespace after a bare colon " \
         "in #{text.inspect}" do
        expect { Sirena::Engine.new.render(text) }
          .to raise_error(Sirena::Parser::ParseError, /Parse error/)
      end
    end

    it "accepts horizontal whitespace after a bare colon" do
      state = rendered_state("stateDiagram-v2\nA : \n", "A")

      expect(child_texts(state)).to eq(["A"])
    end
  end

  describe "DiagramRegistry integration" do
    it "has state_diagram registered" do
      expect(Sirena::DiagramRegistry.registered?(:state_diagram)).to be true
    end

    it "retrieves state diagram handlers" do
      handlers = Sirena::DiagramRegistry.get(:state_diagram)

      expect(handlers).not_to be_nil
      expect(handlers[:parser]).to eq(described_class)
      expect(handlers[:transform]).to eq(Sirena::Layout::StateDiagram)
      expect(handlers[:renderer]).to eq(Sirena::Renderer::StateDiagram)
    end
  end

  # The regression net for the corpus burndown: every state case mmdc
  # 11.12.0 renders has to survive the whole Engine path and come back as
  # SVG a parser accepts.
  describe "the oracle-valid corpus" do
    # A count tripwire, not a behaviour spec: it catches changes to the total
    # number of oracle-valid cases represented by the generated list below.
    # A COUNT-ONLY TRIPWIRE, and deliberately weak: its job is to fail if the
    # corpus or the verdict file moves under the examples below, not to prove
    # behaviour. A same-count swap slips past it, which is recorded as a Low
    # rather than fixed, because per-case identity belongs to the scoreboard
    # (TODO.foundation item 02), not here.
    it "still finds the 52 cases the examples below were generated from" do
      expect(StateDiagramOracleCases.oracle_valid_cases.length).to eq(52)
    end

    mermaid_root = "#{SpecSupport::RepositoryPaths.path('spec/mermaid')}/"
    StateDiagramOracleCases.oracle_valid_cases.each do |path|
      it "renders #{path.delete_prefix(mermaid_root)}" do
        svg = Sirena::Engine.new.render(File.read(path))

        expect(svg).to start_with("<svg")
        expect { REXML::Document.new(svg) }.not_to raise_error
      end
    end
  end
end
