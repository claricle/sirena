# frozen_string_literal: true

require "spec_helper"

module StateDiagramSpecBuilders
  def state_node(id, label, state_type: "normal", **attributes)
    Sirena::Diagram::StateNode.new(
      id: id, label: label, state_type: state_type, **attributes,
    )
  end

  def state_transition(from_id, to_id, **attributes)
    Sirena::Diagram::StateTransition.new(
      from_id: from_id, to_id: to_id, **attributes,
    )
  end

  def rebuild(diagram, states, transitions)
    diagram.states.clear
    diagram.transitions.clear
    diagram.states.concat(states)
    diagram.transitions.concat(transitions)
  end

  def node_in(scene, id)
    scene.children.find { |state| state.id == id }
  end

  def first_state_labels(source)
    diagram = Sirena::Parser::StateDiagram.new.parse(source)
    described_class.new.to_graph(diagram).children.first.labels.map(&:text)
  end

  def aliased_description_source
    <<~MERMAID
      stateDiagram-v2
      state "ALIAS_ONE" as A
      A : DESC_ONE
      state "ALIAS_TWO" as A
      A : DESC_TWO
    MERMAID
  end
end

RSpec.describe Sirena::Layout::StateDiagram, :aggregate_failures do
  include StateDiagramSpecBuilders

  let(:transform) { described_class.new }
  let(:high_contrast) { Sirena::Theme::Registry.get(:high_contrast) }
  let(:engine_source) do
    <<~MERMAID
      stateDiagram-v2
      direction TB
      A --> B
      B --> C
    MERMAID
  end
  let(:section_graph) do
    {
      id: "s",
      children: [
        { id: "a", x: 10, y: 20, width: 100, height: 50 },
        { id: "b", x: 210, y: 20, width: 100, height: 50 },
      ],
      edges: [
        { id: "bent", sources: ["a"], targets: ["b"],
          sections: [{ startPoint: { x: 110, y: 45 },
                       endPoint: { x: 160, y: 80 },
                       bendPoints: [{ x: 135, y: 60 }] },
                     { startPoint: { x: 160, y: 80 },
                       endPoint: { x: 210, y: 45 } }] },
        { id: "straight", sources: ["a"], targets: ["b"] },
      ],
    }
  end

  def final_state_for(child)
    graph = { id: "s", children: [child], edges: [] }
    described_class.from_graph(graph).children.first
  end

  def edge_geometry(scene)
    bent, straight = scene.edges
    bend = bent.sections.first.bend_points.first
    [bent.path, [bend.x, bend.y], straight.path]
  end

  def theme_geometry(scene, default_scene)
    state = scene.children.first
    default_state = default_scene.children.first
    edge_label = scene.edges.first.labels.first
    [state.labels.map(&:font_size), edge_label.font_size,
     state.width > default_state.width]
  end

  def scene_bytes(input)
    Marshal.dump(described_class.new.to_graph(input))
  end

  def parsed_ir_compatibility
    diagram = Sirena::Parser::StateDiagram.new.parse(<<~MERMAID)
      stateDiagram-v2
      direction LR
      [*] --> Parent
      state "Container" as Parent {
        state "Child label" as Child
        Child --> Done : finish [ready]
      }
      state Decision <<choice>>
      Parent --> Decision : decide
      note right of Parent : current state
      Decision --> [*]
    MERMAID
    before = Marshal.dump(diagram)
    graph = Sirena::Notation::Mermaid::IRAdapters::StateDiagram.call(diagram)
    [scene_bytes(graph) == scene_bytes(diagram),
     Marshal.dump(diagram) == before]
  end

  def direct_child_compatibility
    child = Sirena::Diagram::StateNode.new(id: "child", label: "Child")
    parent = Sirena::Diagram::StateNode.new(
      id: "parent", label: "Parent", children: [child],
    )
    sink = Sirena::Diagram::StateNode.new(id: "sink", label: "Sink")
    transition = Sirena::Diagram::StateTransition.new(
      from_id: "parent", to_id: "sink", trigger: "leave",
    )
    diagram = Sirena::Diagram::StateDiagram.new(
      states: [parent, sink], transitions: [transition],
    )
    graph = Sirena::Notation::Mermaid::IRAdapters::StateDiagram.call(diagram)
    [scene_bytes(graph) == scene_bytes(diagram),
     transform.to_graph(graph).children.map(&:id) == %w[parent sink]]
  end

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
    end

    it "converts states and transitions to final nodes and edges" do
      scene = transform.to_graph(diagram)

      expect(scene.children).to all(be_a(described_class::Node))
      expect(scene.edges).to all(be_a(described_class::Edge))
    end

    it "sizes the final-coordinate Scene" do
      scene = transform.to_graph(diagram)

      expect([scene.width, scene.height, scene.view_box])
        .to eq([460.828125, 190.0, "0 0 460.828125 190.0"])
    end

    it "creates one state per declared state" do
      expect(transform.to_graph(diagram).children.length).to eq(2)
    end

    it "gives a created state positive dimensions" do
      idle = node_in(transform.to_graph(diagram), "idle")

      expect(idle).not_to be_nil
      expect(idle.width).to be > 0
      expect(idle.height).to be > 0
    end

    it "keeps a created state's label, type and position" do
      idle = node_in(transform.to_graph(diagram), "idle")

      expect(idle.labels.first.text).to eq("Idle")
      expect(idle.state_type).to eq("normal")
      expect([idle.x, idle.y]).to eq([50.0, 50.0])
    end

    it "creates one transition per declared transition" do
      expect(transform.to_graph(diagram).edges.length).to eq(1)
    end

    it "carries the transition's source, target and trigger" do
      transition = transform.to_graph(diagram).edges.first

      expect([transition.source, transition.target, transition.trigger])
        .to eq(%w[idle active start])
    end

    it "gives the transition a section and path" do
      transition = transform.to_graph(diagram).edges.first

      expect(transition.sections.first).to be_a(described_class::Section)
      expect(transition.path).to eq("M 71.40625 70 L 330.4140625 70")
    end

    context "with a start state" do
      before do
        rebuild(diagram,
                [state_node("start_1", "[*]", state_type: "start"),
                 state_node("idle", "Idle")],
                [state_transition("start_1", "idle")])
      end

      it "handles start state dimensions" do
        start = node_in(transform.to_graph(diagram), "start_1")

        expect([start.width, start.height]).to eq([30, 30])
      end

      it "places the start circle's centre and radius" do
        start = node_in(transform.to_graph(diagram), "start_1")

        expect([start.center_x, start.center_y, start.radius])
          .to eq([21.40625, 15.0, 7.0])
      end
    end

    it "provides both final radii for an end state" do
      state = final_state_for(
        id: "end", x: 10, y: 20, width: 30, height: 30,
        metadata: { state_type: "end" }
      )
      expect([state.radius, state.inner_radius]).to eq([15.0, 10.0])
    end

    context "with a choice state" do
      before do
        rebuild(diagram,
                [state_node("choice1", "choice1", state_type: "choice"),
                 state_node("idle", "Idle")],
                [state_transition("choice1", "idle")])
      end

      it "handles choice state dimensions" do
        choice = node_in(transform.to_graph(diagram), "choice1")

        expect([choice.width, choice.height]).to all(be > 0)
      end

      it "keeps the choice type and its diamond points" do
        choice = node_in(transform.to_graph(diagram), "choice1")

        expect(choice.state_type).to eq("choice")
        expect(choice.shape_points.split).to have_attributes(length: 4)
      end
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

    it "lets Engine select ELK for an acyclic DOWN diagram" do
      elk = Sirena::Engine.new.render(engine_source, layout_engine: :elk)
      grid = Sirena::Engine.new.render(engine_source)
      expect(elk).not_to eq(grid)
    end

    it "lets Engine select ELK for an acyclic RIGHT diagram" do
      source = engine_source.sub("direction TB", "direction LR")
      elk = Sirena::Engine.new.render(source, layout_engine: :elk)
      expect(elk).not_to eq(Sirena::Engine.new.render(source))
    end

    # A REGRESSION GUARD for pre-existing transform behaviour. The branch
    # rewrote how transition endpoints resolve, so this is the invariant that
    # must survive; it is green on origin/main by design.
    it "raises error when a transition names a state that does not exist" do
      invalid = Sirena::Diagram::StateDiagram.new
      rebuild(invalid, [state_node("idle", "Idle")],
              [state_transition("idle", "nowhere")])

      expect { transform.to_graph(invalid) }
        .to raise_error(Sirena::Layout::LayoutError)
    end

    it "transforms a diagram with no states at all" do
      scene = transform.to_graph(Sirena::Diagram::StateDiagram.new)

      expect(scene.children).to eq([])
      expect(scene.edges).to eq([])
      expect(scene.id).to eq("state_diagram")
      expect([scene.width, scene.height]).to eq([900.0, 700.0])
    end

    context "with a described state" do
      before do
        rebuild(diagram,
                [state_node("idle", "Idle", description: "System is idle"),
                 state_node("active", "Active")],
                [state_transition("idle", "active")])
      end

      it "includes the description in labels when present" do
        state = node_in(transform.to_graph(diagram), "idle")

        expect(state.labels.length).to eq(2)
      end

      it "orders the label before the description" do
        state = node_in(transform.to_graph(diagram), "idle")

        expect(state.labels.map(&:text)).to eq(["Idle", "System is idle"])
      end
    end

    it "uses a bare description as the only display text" do
      expect(first_state_labels("stateDiagram-v2\nA : ONLY_TEXT\n"))
        .to eq(["ONLY_TEXT"])
    end

    it "preserves aliases and descriptions in source order" do
      expect(first_state_labels(aliased_description_source))
        .to eq(%w[ALIAS_ONE DESC_ONE ALIAS_TWO DESC_TWO])
    end

    # A label is deliberately NOT display text for shape purposes, because
    # terminals carry `label: "[*]"` with no descriptions — keying the shape on
    # the label turns `[*]` into an ordinary 100px box instead of a 30px circle.
    # No parsed source produces a marker with a label and no descriptions, so
    # only a directly built model can hold that combination.
    it "keeps a marker type when only a scalar label is set" do
      labelled = state_node("C", "C", state_type: "choice")

      expect(transform.send(:state_shape_type, labelled)).to eq("choice")
    end

    it "gives a marker with descriptions the normal shape" do
      described = Sirena::Diagram::StateNode.new(
        id: "D", state_type: "choice", descriptions: ["text"],
      )

      expect(transform.send(:state_shape_type, described)).to eq("normal")
    end

    it "preserves final section points and missing edge geometry" do
      scene = described_class.from_graph(section_graph)
      expect(edge_geometry(scene)).to eq(
        ["M 110 45 L 135 60 L 160 80 M 160 80 L 210 45",
         [135.0, 60.0], "M 60 45 L 260 45"],
      )
    end

    it "uses fixed measurement size and themed final text geometry" do
      source = "stateDiagram-v2\nA : description\nA --> B : go\n"
      diagram = Sirena::Parser::StateDiagram.new.parse(source)
      scene = transform.call(diagram, theme: high_contrast)
      default_scene = described_class.new.to_graph(diagram)
      expect(theme_geometry(scene, default_scene)).to eq([[16.0], 14.0, false])
    end

    it "keeps parsed nesting, transitions, and notes byte-identical via IR" do
      expect(parsed_ir_compatibility).to all(be(true))
    end

    it "accepts shared IR while retaining direct child layout behavior" do
      expect(direct_child_compatibility).to all(be(true))
    end
  end
end
