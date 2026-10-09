# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  let(:transform) { described_class.new }

  describe "#to_graph" do
    let(:diagram) do
      Sirena::Diagram::StateDiagram.new(direction: "TD").tap do |d|
        d.states << Sirena::Diagram::StateNode.new(
          id: "idle",
          label: "Idle",
          state_type: "normal",
        )
        d.states << Sirena::Diagram::StateNode.new(
          id: "active",
          label: "Active",
          state_type: "normal",
        )
        d.transitions << Sirena::Diagram::StateTransition.new(
          from_id: "idle",
          to_id: "active",
          trigger: "start",
        )
      end
    end

    it "converts the diagram to a final-coordinate Scene" do
      scene = transform.to_graph(diagram)

      expect(scene).to be_a(described_class::Scene)
      expect(scene.id).to eq("state_diagram")
      expect(scene.children).to all(be_a(described_class::Node))
      expect(scene.edges).to all(be_a(described_class::Edge))
      expect([scene.width, scene.height, scene.view_box])
        .to eq([500.0, 200.0, "0 0 500 200"])
    end

    it "creates states with dimensions" do
      scene = transform.to_graph(diagram)

      expect(scene.children.length).to eq(2)

      state_idle = scene.children.find { |state| state.id == "idle" }
      expect(state_idle).not_to be_nil
      expect(state_idle.width).to be > 0
      expect(state_idle.height).to be > 0
      expect(state_idle.labels.first.text).to eq("Idle")
      expect(state_idle.state_type).to eq("normal")
      expect([state_idle.x, state_idle.y]).to eq([50.0, 50.0])
    end

    it "creates transitions with metadata" do
      scene = transform.to_graph(diagram)

      expect(scene.edges.length).to eq(1)

      transition = scene.edges.first
      expect([transition.source, transition.target, transition.trigger])
        .to eq(%w[idle active start])
      expect(transition.sections.first).to be_a(described_class::Section)
      expect(transition.path).to eq("M 100 75 L 350 75")
    end

    it "handles start state dimensions" do
      diagram.states.clear
      diagram.transitions.clear
      diagram.states << Sirena::Diagram::StateNode.new(
        id: "start_1",
        label: "[*]",
        state_type: "start",
      )
      diagram.states << Sirena::Diagram::StateNode.new(
        id: "idle",
        label: "Idle",
        state_type: "normal",
      )
      diagram.transitions << Sirena::Diagram::StateTransition.new(
        from_id: "start_1",
        to_id: "idle",
      )

      scene = transform.to_graph(diagram)

      start = scene.children.find { |state| state.id == "start_1" }
      expect(start.width).to eq(30)
      expect(start.height).to eq(30)
      expect([start.center_x, start.center_y, start.radius])
        .to eq([65.0, 65.0, 15.0])
    end

    it "provides both final radii for an end state" do
      graph = {
        id: "s",
        children: [
          { id: "end", x: 10, y: 20, width: 30, height: 30,
            metadata: { state_type: "end" } },
        ],
        edges: [],
      }

      state = described_class.from_graph(graph).children.first

      expect([state.radius, state.inner_radius]).to eq([15.0, 10.0])
    end

    it "handles choice state dimensions" do
      diagram.states.clear
      diagram.transitions.clear
      diagram.states << Sirena::Diagram::StateNode.new(
        id: "choice1",
        label: "choice1",
        state_type: "choice",
      )
      diagram.states << Sirena::Diagram::StateNode.new(
        id: "idle",
        label: "Idle",
        state_type: "normal",
      )
      diagram.transitions << Sirena::Diagram::StateTransition.new(
        from_id: "choice1",
        to_id: "idle",
      )

      scene = transform.to_graph(diagram)

      choice = scene.children.find { |state| state.id == "choice1" }
      expect(choice.width).to be > 0
      expect(choice.height).to be > 0
      expect(choice.state_type).to eq("choice")
      expect(choice.shape_points.split).to have_attributes(length: 4)
    end

    it "sets layout options based on direction" do
      graph = transform.send(:build_graph, diagram)

      options = graph[:layoutOptions]
      expect(options["elk.algorithm"]).to eq("layered")
      expect(options["elk.direction"]).to eq("DOWN")
    end

    it "converts LR direction to RIGHT layout" do
      diagram.direction = "LR"
      graph = transform.send(:build_graph, diagram)

      expect(graph[:layoutOptions]["elk.direction"]).to eq("RIGHT")
    end

    # A REGRESSION GUARD for pre-existing transform behaviour. The branch
    # rewrote how transition endpoints resolve, so this is the invariant that
    # must survive; it is green on origin/main by design.
    it "raises error when a transition names a state that does not exist" do
      invalid_diagram = Sirena::Diagram::StateDiagram.new
      invalid_diagram.states << Sirena::Diagram::StateNode.new(
        id: "idle", label: "Idle", state_type: "normal",
      )
      invalid_diagram.transitions << Sirena::Diagram::StateTransition.new(
        from_id: "idle", to_id: "nowhere",
      )

      expect do
        transform.to_graph(invalid_diagram)
      end.to raise_error(Sirena::Layout::LayoutError)
    end

    it "transforms a diagram with no states at all" do
      scene = transform.to_graph(Sirena::Diagram::StateDiagram.new)

      expect(scene.children).to eq([])
      expect(scene.edges).to eq([])
      expect(scene.id).to eq("state_diagram")
      expect([scene.width, scene.height]).to eq([900.0, 700.0])
    end

    it "includes description in labels when present" do
      diagram.states.clear
      diagram.transitions.clear
      diagram.states << Sirena::Diagram::StateNode.new(
        id: "idle",
        label: "Idle",
        state_type: "normal",
        description: "System is idle",
      )
      diagram.states << Sirena::Diagram::StateNode.new(
        id: "active",
        label: "Active",
        state_type: "normal",
      )
      diagram.transitions << Sirena::Diagram::StateTransition.new(
        from_id: "idle",
        to_id: "active",
      )

      scene = transform.to_graph(diagram)

      state = scene.children.find { |child| child.id == "idle" }
      expect(state.labels.length).to eq(2)
      expect(state.labels.map(&:text)).to eq(["Idle", "System is idle"])
    end

    it "uses a bare description as the only display text" do
      diagram = Sirena::Parser::StateDiagram.new.parse(
        "stateDiagram-v2\nA : ONLY_TEXT\n",
      )

      scene = transform.to_graph(diagram)
      labels = scene.children.first.labels.map(&:text)

      expect(labels).to eq(["ONLY_TEXT"])
    end

    it "preserves aliases and descriptions in source order" do
      diagram = Sirena::Parser::StateDiagram.new.parse(<<~MERMAID)
        stateDiagram-v2
        state "ALIAS_ONE" as A
        A : DESC_ONE
        state "ALIAS_TWO" as A
        A : DESC_TWO
      MERMAID

      scene = transform.to_graph(diagram)
      labels = scene.children.first.labels.map(&:text)

      expect(labels).to eq(
        %w[ALIAS_ONE DESC_ONE ALIAS_TWO DESC_TWO],
      )
    end

    # A label is deliberately NOT display text for shape purposes, because
    # terminals carry `label: "[*]"` with no descriptions — keying the shape on
    # the label turns `[*]` into an ordinary 100px box instead of a 30px circle.
    # No parsed source produces a marker with a label and no descriptions, so
    # only a directly built model can hold that combination.
    it "keeps a marker type when only a scalar label is set" do
      labelled = Sirena::Diagram::StateNode.new(
        id: "C", label: "C", state_type: "choice",
      )
      described = Sirena::Diagram::StateNode.new(
        id: "D", state_type: "choice", descriptions: ["text"],
      )

      expect(transform.send(:state_shape_type, labelled)).to eq("choice")
      expect(transform.send(:state_shape_type, described)).to eq("normal")
    end

    it "preserves final section points and missing edge geometry" do
      graph = {
        id: "s",
        children: [
          { id: "a", x: 10, y: 20, width: 100, height: 50 },
          { id: "b", x: 210, y: 20, width: 100, height: 50 },
        ],
        edges: [
          { id: "bent", sources: ["a"], targets: ["b"],
            sections: [{ startPoint: { x: 110, y: 45 },
                         endPoint: { x: 210, y: 45 },
                         bendPoints: [{ x: 160, y: 80 }] }] },
          { id: "straight", sources: ["a"], targets: ["b"] },
        ],
      }

      scene = described_class.from_graph(graph)
      bent, straight = scene.edges

      expect(bent.path).to eq("M 110 45 L 160 80 L 210 45")
      expect(bent.sections.first.bend_points.first)
        .to have_attributes(x: 160.0, y: 80.0)
      expect(straight.path).to eq("M 60 45 L 260 45")
    end

    it "uses one theme size for measurement and final text geometry" do
      source = "stateDiagram-v2\nA : description\nA --> B : go\n"
      diagram = Sirena::Parser::StateDiagram.new.parse(source)

      scene = transform.call(
        diagram, theme: Sirena::Theme::Registry.get(:high_contrast)
      )

      expect(scene.children.first.labels.map(&:font_size)).to eq([16.0])
      expect(scene.edges.first.labels.first.font_size).to eq(14.0)
      default_scene = described_class.new.to_graph(diagram)
      expect(scene.children.first.width).to be > default_scene.children.first.width
    end
  end
end
