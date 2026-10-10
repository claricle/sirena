# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Sequence do
  subject(:renderer) { described_class.new }

  let(:svg) { Sirena::Svg::Document.new }
  let(:group) { Sirena::Svg::Group.new }
  let(:scene) do
    Sirena::Layout::Sequence::Scene.new(id: "s", width: 300, height: 200)
  end
  let(:noting_class) do
    Class.new(described_class) do
      def seen = @seen ||= []

      def render_notes(notes, _positions, _svg)
        seen << notes
      end
    end
  end

  def style(line)
    { line: line, head: "arrow" }
  end

  def hook(name, *arguments)
    renderer.send(name, *arguments)
  end

  def dashes(element_class)
    group.children.grep(element_class).map(&:stroke_dasharray)
  end

  describe "hash graphs" do
    it "renders participants of a graph without edges or notes" do
      graph = { children: [{ id: "A", labels: [{ text: "A", width: 10 }] }] }

      expect(renderer.render(graph).to_xml).to include(">A<")
    end

    it "hands the notes of a graph to the note hook" do
      noting = noting_class.new
      noting.render({ children: [], metadata: { notes: [:note] } })

      expect(noting.seen).to eq([[:note]])
    end

    it "does not call the note hook for a graph without notes" do
      noting = noting_class.new
      noting.render({ children: [] })

      expect(noting.seen).to be_empty
    end

    it "skips a participant that has no position" do
      hook(:render_participant, { id: "A" }, {}, svg)

      expect(svg.children).to be_empty
    end

    it "skips a message whose endpoints have no position" do
      hook(:render_message, { sources: ["A"], targets: ["B"] }, {}, 0, svg)

      expect(svg.children).to be_empty
    end
  end

  describe "typed input to the compatibility hooks" do
    it "takes the canvas width from a scene" do
      expect(hook(:calculate_width, scene)).to eq(300 - 40)
    end

    it "takes the canvas height from a scene" do
      expect(hook(:calculate_height, scene)).to eq(200 - 40)
    end

    it "draws a typed participant as given" do
      participant = Sirena::Layout::Sequence::Participant.new(id: "p")
      hook(:render_participant, participant, {}, svg)

      expect(svg.children.size).to eq(1)
    end

    it "draws a typed message as given" do
      message = Sirena::Layout::Sequence::Message.new(id: "m")
      hook(:render_message, message, {}, 0, svg)

      expect(svg.children.size).to eq(1)
    end

    it "draws the messages of a scene" do
      scene.messages = [Sirena::Layout::Sequence::Message.new(id: "m")]
      hook(:render_messages, scene, {}, svg)

      expect(svg.children.size).to eq(1)
    end
  end

  describe "arrow hooks" do
    it "draws a self message as a loop path" do
      hook(:render_self_message, 50, 80, style("solid"), group)

      expect(group.children.grep(Sirena::Svg::Path).size).to eq(1)
    end

    it "dashes the loop path of a dotted self message" do
      hook(:render_self_message, 50, 80, style("dotted"), group)

      expect(dashes(Sirena::Svg::Path)).to eq(["5,5"])
    end

    it "draws a solid arrow shaft without a dash" do
      hook(:render_arrow, 10, 50, 90, 50, style("solid"), group)

      expect(dashes(Sirena::Svg::Line)).to eq([nil])
    end

    it "dashes the shaft of a dotted arrow" do
      hook(:render_arrow, 10, 50, 90, 50, style("dotted"), group)

      expect(dashes(Sirena::Svg::Line)).to eq(["5,5"])
    end

    it "draws only the heads of geometry without a shaft" do
      hook(:draw_arrow_geometry, { heads: [] }, style("solid"), group)

      expect(group.children).to be_empty
    end

    it "dashes a dotted message line" do
      span = { x1: 10, y1: 50, x2: 90, y2: 50 }

      expect(hook(:message_line, span, style("dotted"), [:target]).stroke_dasharray)
        .to eq("5,5")
    end

    it "leaves a solid message line undashed" do
      span = { x1: 10, y1: 50, x2: 90, y2: 50 }

      expect(hook(:message_line, span, style("solid"), [:target]).stroke_dasharray)
        .to be_nil
    end
  end
end
