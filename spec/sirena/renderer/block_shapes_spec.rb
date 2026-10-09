# frozen_string_literal: true

require "spec_helper"

module BlockShapesHelpers
  def node(id, label: id, children: [], **attrs)
    Sirena::Diagram::BlockNode.new.tap do |b|
      b.id = id
      b.label = label
      attrs.each { |name, value| b.public_send("#{name}=", value) }
      children.each { |c| b.add_child(c) }
    end
  end

  def info(block, parent_id: nil, **box)
    { block: block, x: 0, y: 0, width: 100, height: 60,
      parent_id: parent_id }.merge(box)
  end
end

RSpec.describe Sirena::Renderer::Block do
  include BlockShapesHelpers

  let(:renderer) { described_class.new(theme: Sirena::Theme::Registry.get(:default)) }
  let(:xml) { renderer.render(layout).to_xml }

  context "with an empty layout" do
    let(:layout) { {} }

    it "falls back to the default 800x600 canvas with no blocks",
       :aggregate_failures do
      doc = renderer.render(layout)
      expect([doc.width, doc.height]).to eq([800, 600])
      expect(xml).not_to include("block-")
    end
  end

  context "with arrow-shaped blocks in every direction" do
    let(:layout) do
      blocks = %w[up down left right sideways].to_h do |dir|
        [dir, info(node(dir, shape: "arrow", direction: dir, label: ""))]
      end
      { blocks: blocks }
    end

    it "draws a triangle pointing the requested way", :aggregate_failures do
      expect(xml).to include('points="50,0 100,60 0,60"')   # up
      expect(xml).to include('points="0,0 100,0 50,60"')    # down
      expect(xml).to include('points="0,30 100,0 100,60"')  # left
      # right, and the fallback
      expect(xml.scan('points="0,0 100,30 0,60"').size).to eq(2)
    end

    it "omits the label element for empty labels" do
      expect(xml).not_to include("<text")
    end
  end

  context "with a circle block" do
    let(:layout) do
      { blocks: { "c" => info(node("c", shape: "circle"), width: 80,
                                                          height: 40) } }
    end

    it "uses the smaller side as the radius around the centre" do
      expect(xml).to match(/<circle[^>]*cx="40.0"[^>]*cy="20.0"[^>]*r="20.0"/)
    end
  end

  context "with a compound block holding rendered, space and unlaid kids" do
    let(:layout) do
      child = node("kid", label: "Kid")
      space = node("gap", block_type: "space")
      parent = node("grp", is_compound: true,
                           children: [child, space, node("ghost")])
      {
        blocks: {
          "grp" => info(parent, width: 300, height: 200),
          "kid" => info(child, x: 10, y: 10, parent_id: "grp"),
          "gap" => info(space, parent_id: "grp"),
        },
      }
    end

    it "draws a dashed border and the laid-out child inside the compound group",
       :aggregate_failures do
      expect(xml).to include('stroke-dasharray="5,5"')
      expect(xml).to include('id="block-kid"')
      expect(xml).to include(">Kid<")
    end

    it "skips space children and children without layout info",
       :aggregate_failures do
      expect(xml).not_to include("block-gap")
      expect(xml).not_to include("block-ghost")
    end

    it "does not emit the child group at top level a second time" do
      expect(xml.scan('id="block-kid"').size).to eq(1)
    end
  end

  context "with a space block among top-level blocks" do
    let(:layout) do
      { blocks: { "s" => info(node("s", block_type: "space")),
                  "a" => info(node("a")) } }
    end

    it "renders only the real block", :aggregate_failures do
      expect(xml).to include('id="block-a"')
      expect(xml).not_to include('id="block-s"')
    end
  end

  context "with a nil label" do
    let(:layout) { { blocks: { "n" => info(node("n", label: nil)) } } }

    it "renders the shape without text", :aggregate_failures do
      expect(xml).to include('id="block-n"')
      expect(xml).not_to include("<text")
    end
  end

  context "with a childless-label child in a compound" do
    let(:kid) { node("k", label: nil) }
    let(:layout) do
      parent = node("g", is_compound: true, children: [kid])
      { blocks: { "g" => info(parent), "k" => info(kid, parent_id: "g") } }
    end

    it "renders the child shape without text", :aggregate_failures do
      expect(xml).to include('id="block-k"')
      expect(xml).not_to include("<text")
    end
  end

  context "with connections" do
    let(:layout) do
      {
        connections: [
          { from: "a", to: "b", from_x: 1, from_y: 2, to_x: 3, to_y: 4,
            connection_type: "arrow" },
          { from: "b", to: "c", from_x: 5, from_y: 6, to_x: 7, to_y: 8,
            connection_type: "line" },
        ],
      }
    end

    it "draws straight paths and an arrowhead only for arrows",
       :aggregate_failures do
      expect(xml).to include('d="M 1 2 L 3 4"')
      expect(xml).to include('d="M 5 6 L 7 8"')
      expect(xml.scan("<polygon").size).to eq(1)
    end
  end
end
