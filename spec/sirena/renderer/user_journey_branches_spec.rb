# frozen_string_literal: true

require "spec_helper"
require "sirena/renderer/user_journey"

RSpec.describe Sirena::Renderer::UserJourney do
  subject(:renderer) { described_class.new }

  def xml_for(graph)
    renderer.render(graph).to_xml
  end

  def task_node(id, **metadata)
    { id: id, metadata: metadata }
  end

  describe "canvas size" do
    it "is 400 wide and 45 tall for a journey with no tasks" do
      xml = xml_for({ id: "u" })
      expect(xml).to include('width="400.0"').and include('height="45.0"')
    end

    it "reserves 70 more for a title" do
      xml = xml_for({ id: "u", metadata: { title: "T" } })
      expect(xml).to include('viewBox="0 -25 400 90"')
    end

    it "reserves room for 200px per task plus both margins" do
      xml = xml_for({ id: "u", children: [task_node("a"), task_node("b")] })
      expect(xml).to include('viewBox="0 -25 700 470"')
    end
  end

  describe "tasks" do
    let(:scored) do
      task_node("t2", name: "N", score: 4, actors: %w[Me You],
                      section_name: "S")
    end

    it "gives a bare task a flat mouth, the score 3 face" do
      xml = xml_for({ id: "u", children: [task_node("t1")] })
      expect(xml).to include('class="mouth" stroke="#666"')
    end

    it "draws a smile above score 3" do
      xml = xml_for({ id: "u", children: [scored] })
      expect(xml).to include('d="M7.5,0A7.5,7.5')
    end

    it "hangs the face at 300 plus 30 per point below 5" do
      xml = xml_for({ id: "u", children: [scored] })
      expect(xml).to include('cx="225.0" cy="330.0" r="15.0"')
    end

    it "lists every actor once in the legend" do
      xml = xml_for({ id: "u", children: [scored] })
      expect(xml.scan(/>(Me|You)</).flatten).to eq(%w[Me You])
    end

    it "draws no band for tasks outside any section" do
      xml = xml_for({ id: "u", children: [task_node("t1")] })
      expect(xml).not_to include("journey-section")
    end

    it "draws one band over tasks sharing a section" do
      children = [scored, scored.merge(id: "t3")]
      xml = xml_for({ id: "u", children: children })
      expect(xml).to include('x="150.0" y="50.0" width="350.0"')
    end

    it "skips the title when it is empty" do
      graph = { id: "u", children: [task_node("t1")] }
      xml = xml_for(graph.merge(metadata: { title: "" }))
      expect(xml).not_to include('font-weight="bold"')
    end

    it "puts the title at the left margin, 25 down" do
      xml = xml_for({ id: "u", metadata: { title: "T" } })
      expect(xml).to include('x="150.0" y="25.0"')
    end
  end

  describe "timeline arrow" do
    it "is one black line at y=200, ended short of the right margin" do
      xml = xml_for({ id: "u" })
      expect(xml).to include('x1="150.0" y1="200.0" x2="246.0" y2="200.0"')
    end
  end
end
