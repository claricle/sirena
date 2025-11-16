# frozen_string_literal: true

require 'spec_helper'
require 'sirena/renderer/treemap'
require 'sirena/diagram/treemap'

RSpec.describe Sirena::Renderer::Treemap do
  let(:diagram) { Sirena::Diagram::TreemapDiagram.new }
  let(:transform) { Sirena::Transform::Treemap.new }
  let(:renderer) { described_class.new }

  describe '#render' do
    context 'with basic treemap' do
      it 'renders simple treemap with one node' do
        root = Sirena::Diagram::TreemapNode.new('Root')
        child = Sirena::Diagram::TreemapNode.new('Child', 100)
        root.add_child(child)
        diagram.add_root_node(root)

        layout = transform.to_graph(diagram)
        svg = renderer.render(layout)

        expect(svg).to include('<svg')
        expect(svg).to include('</svg>')
        expect(svg).to include('Root')
        expect(svg).to include('Child')
      end

      it 'renders with title' do
        diagram.title = 'My Treemap'
        root = Sirena::Diagram::TreemapNode.new('Root', 100)
        diagram.add_root_node(root)

        layout = transform.to_graph(diagram)
        svg = renderer.render(layout)

        expect(svg).to include('My Treemap')
      end
    end

    context 'with multiple nodes' do
      it 'renders multiple root nodes' do
        root1 = Sirena::Diagram::TreemapNode.new('Section 1')
        child1 = Sirena::Diagram::TreemapNode.new('Leaf 1', 50)
        root1.add_child(child1)

        root2 = Sirena::Diagram::TreemapNode.new('Section 2')
        child2 = Sirena::Diagram::TreemapNode.new('Leaf 2', 30)
        root2.add_child(child2)

        diagram.add_root_node(root1)
        diagram.add_root_node(root2)

        layout = transform.to_graph(diagram)
        svg = renderer.render(layout)

        expect(svg).to include('Section 1')
        expect(svg).to include('Section 2')
        expect(svg).to include('Leaf 1')
        expect(svg).to include('Leaf 2')
      end

      it 'renders nested hierarchy' do
        root = Sirena::Diagram::TreemapNode.new('Level 1')
        level2 = Sirena::Diagram::TreemapNode.new('Level 2')
        level3 = Sirena::Diagram::TreemapNode.new('Level 3', 100)

        level2.add_child(level3)
        root.add_child(level2)
        diagram.add_root_node(root)

        layout = transform.to_graph(diagram)
        svg = renderer.render(layout)

        expect(svg).to include('Level 1')
        expect(svg).to include('Level 2')
        expect(svg).to include('Level 3')
      end
    end

    context 'with styling' do
      it 'applies different colors to different depth levels' do
        root = Sirena::Diagram::TreemapNode.new('Root')
        child1 = Sirena::Diagram::TreemapNode.new('Child1', 50)
        child2 = Sirena::Diagram::TreemapNode.new('Child2', 50)

        root.add_child(child1)
        root.add_child(child2)
        diagram.add_root_node(root)

        layout = transform.to_graph(diagram)
        svg = renderer.render(layout)

        # Should have colored rectangles
        expect(svg).to include('<rect')
        expect(svg).to include('fill=')
      end

      it 'applies CSS class styles when defined' do
        diagram.add_class_def('important', 'fill:#f96,stroke:#333')

        root = Sirena::Diagram::TreemapNode.new('Root')
        child = Sirena::Diagram::TreemapNode.new('Important', 100)
        child.css_class = 'important'

        root.add_child(child)
        diagram.add_root_node(root)

        layout = transform.to_graph(diagram)
        svg = renderer.render(layout)

        # Should use the custom fill color
        expect(svg).to include('#f96')
      end
    end

    context 'with values' do
      it 'displays values for leaf nodes' do
        root = Sirena::Diagram::TreemapNode.new('Root')
        child = Sirena::Diagram::TreemapNode.new('Leaf', 123)
        root.add_child(child)
        diagram.add_root_node(root)

        layout = transform.to_graph(diagram)
        svg = renderer.render(layout)

        expect(svg).to include('123')
      end

      it 'formats decimal values' do
        root = Sirena::Diagram::TreemapNode.new('Root')
        child = Sirena::Diagram::TreemapNode.new('Leaf', 123.7)
        root.add_child(child)
        diagram.add_root_node(root)

        layout = transform.to_graph(diagram)
        svg = renderer.render(layout)

        expect(svg).to include('123.7')
      end
    end

    context 'with empty diagram' do
      it 'renders empty treemap gracefully' do
        layout = transform.to_graph(diagram)
        svg = renderer.render(layout)

        expect(svg).to include('<svg')
        expect(svg).to include('</svg>')
      end
    end
  end
end