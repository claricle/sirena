# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::UserJourney do
  subject(:renderer) { described_class.new }

  let(:svg) { Sirena::Svg::Document.new }
  let(:tasks) do
    [{ id: "a", x: 0, y: 0, width: 100, height: 40 },
     { id: "b", x: 200, y: 0, width: 100, height: 40 }]
  end

  def hook(name, *arguments)
    renderer.send(name, *arguments)
  end

  def group_ids
    svg.children.grep(Sirena::Svg::Group).map(&:id)
  end

  describe "canvas hooks" do
    it "widens the default canvas for a graph without children" do
      expect(hook(:calculate_width, {})).to eq(800)
    end

    it "fits the canvas width to the children" do
      expect(hook(:calculate_width, { children: tasks })).to eq(340)
    end

    it "uses the default height for a graph without children" do
      expect(hook(:calculate_height, {})).to eq(600)
    end

    it "fits the canvas height to the children" do
      expect(hook(:calculate_height, { children: tasks })).to eq(100)
    end

    it "adds title room to the canvas height" do
      graph = { children: tasks, metadata: { title: "T" } }

      expect(hook(:calculate_height, graph)).to be > 100
    end
  end

  describe "section and timeline hooks" do
    it "returns the start position when there are no children" do
      expect(hook(:render_sections_and_tasks, svg, {}, 5)).to eq(5)
    end

    it "moves below the sections it draws" do
      result = hook(:render_sections_and_tasks, svg, { children: tasks }, 5)

      expect(result).to be > 5
    end

    it "draws nothing for a graph without edges" do
      hook(:render_timeline, { children: tasks }, svg)

      expect(svg.children).to be_empty
    end

    it "draws an arrow between two tasks" do
      edge = { id: "e", sources: ["a"], targets: ["b"] }
      hook(:render_timeline, { children: tasks, edges: [edge] }, svg)

      expect(group_ids).to eq(["arrow-e"])
    end

    it "skips an arrow whose source is missing" do
      edge = { id: "e", sources: ["zz"], targets: ["b"] }
      hook(:render_timeline, { children: tasks, edges: [edge] }, svg)

      expect(svg.children).to be_empty
    end

    it "skips an arrow whose target is missing" do
      edge = { id: "e", sources: ["a"], targets: ["zz"] }
      hook(:render_timeline, { children: tasks, edges: [edge] }, svg)

      expect(svg.children).to be_empty
    end

    it "skips an arrow without endpoints" do
      hook(:render_timeline, { children: tasks, edges: [{ id: "e" }] }, svg)

      expect(svg.children).to be_empty
    end

    it "finds no node in a graph without children" do
      expect(hook(:find_node, {}, "a")).to be_nil
    end

    it "finds no node for a missing id" do
      expect(hook(:find_node, { children: [{}] }, nil)).to be_nil
    end
  end
end
