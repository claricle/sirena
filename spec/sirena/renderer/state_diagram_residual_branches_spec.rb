# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::StateDiagram do
  subject(:renderer) { described_class.new }

  let(:source) { { id: "a" } }
  let(:target) { { id: "b", x: 200, y: 0 } }

  def hook(name, *arguments)
    renderer.send(name, *arguments)
  end

  describe "hooks called with plain hashes" do
    it "draws a hash transition between the state centres" do
      expect(hook(:calculate_transition_path, source, target, {}))
        .to eq("M 50 25 L 250 25")
    end

    it "routes a hash transition through its bend points" do
      transition = { sections: [{ bendPoints: [{ x: 5, y: 6 }] }] }

      expect(hook(:calculate_transition_path, source, target, transition))
        .to eq("M 50 25 L 5 6 L 250 25")
    end

    it "places a hash transition label between the states" do
      label = hook(:create_transition_label, source, target, { text: "go" })

      expect([label.x, label.y]).to eq([150.0, 17.0])
    end

    it "places a hash state label inside the state" do
      label = hook(:create_state_label, source, { text: "A" }, 0)

      expect(Array(label.content).join).to eq("A")
    end
  end

  describe "hooks called with typed geometry" do
    let(:typed) { hook(:typed_state, { id: "a", x: 1, y: 2, width: 3, height: 4 }) }

    it "reads the box of a typed state" do
      expect(hook(:compatibility_shape_values, typed, typed, "normal"))
        .to eq([typed.x, typed.y, typed.width, typed.height])
    end
  end

  it "drops a hash transition that names no target" do
    graph = { id: "s", children: [source, target],
              edges: [{ id: "e", sources: ["a"] }] }

    expect(renderer.render(graph).to_xml).not_to include("transition-e")
  end
end
