# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Layout::Flowchart do
  let(:transform) { described_class.new }

  describe '#to_graph' do
    let(:diagram) do
      Sirena::Diagram::Flowchart.new(direction: 'TD').tap do |d|
        d.nodes << Sirena::Diagram::FlowchartNode.new(
          id: 'A',
          label: 'Start',
          shape: 'rect'
        )
        d.nodes << Sirena::Diagram::FlowchartNode.new(
          id: 'B',
          label: 'End',
          shape: 'rect'
        )
        d.edges << Sirena::Diagram::FlowchartEdge.new(
          source_id: 'A',
          target_id: 'B',
          arrow_type: 'arrow'
        )
      end
    end

    it 'converts diagram to graph structure' do
      graph = transform.to_graph(diagram)

      expect(graph).to be_a(Hash)
      expect(graph[:id]).to eq('flowchart')
      expect(graph[:children]).to be_an(Array)
      expect(graph[:edges]).to be_an(Array)
      expect(graph[:layoutOptions]).to be_a(Hash)
    end

    it 'creates nodes with dimensions' do
      graph = transform.to_graph(diagram)

      expect(graph[:children].length).to eq(2)

      node_a = graph[:children].find { |n| n[:id] == 'A' }
      expect(node_a).not_to be_nil
      expect(node_a[:width]).to be > 0
      expect(node_a[:height]).to be > 0
      expect(node_a[:labels]).to be_an(Array)
      expect(node_a[:labels].first[:text]).to eq('Start')
    end

    # `assemble` attaches nested clusters before member nodes, and the
    # order is what the grid slices three to a row: run `place_nodes`
    # first instead and the inner box drops from [20, 54] to the second
    # row, taking the outer box from 308 units tall to 398.
    it 'lists a nested cluster before the nodes beside it' do
      source = "flowchart TD\nsubgraph outer\nsubgraph inner\ni1\nend\n" \
               "n1\nn2\nn3\nend\n"
      model = Sirena::Parser::Flowchart.new.parse(source)

      outer = transform.to_graph(model)[:children]
        .find { |child| child[:id] == 'outer' }

      expect(outer[:children].map { |child| child[:id] })
        .to eq(%w[inner n1 n2 n3])
    end

    it 'emits every node and subgraph when valid model ids repeat' do
      model = Sirena::Diagram::Flowchart.new(direction: 'TD')
      model.nodes.push(
        Sirena::Diagram::FlowchartNode.new(id: 'same', label: 'First'),
        Sirena::Diagram::FlowchartNode.new(id: 'same', label: 'Second'),
        Sirena::Diagram::FlowchartNode.new(id: 'one', label: 'One'),
        Sirena::Diagram::FlowchartNode.new(id: 'two', label: 'Two')
      )
      model.subgraphs.push(
        Sirena::Diagram::FlowchartSubgraph.new(
          id: 'group', declared_title: 'First group', node_ids: %w[one]
        ),
        Sirena::Diagram::FlowchartSubgraph.new(
          id: 'group', declared_title: 'Second group', node_ids: %w[two]
        )
      )

      expect(model).to be_valid

      children = transform.to_graph(model)[:children]
      labels = children.map { |child| child[:labels].first[:text] }
      members = children.select { |child| child.dig(:metadata, :cluster) }
        .to_h do |box|
          title = box[:labels].first[:text]
          held = box[:children].map { |node| node[:labels].first[:text] }
          [title, held]
        end

      expect(labels).to eq(['First', 'Second', 'First group', 'Second group'])
      expect(members).to eq('First group' => %w[One],
                            'Second group' => %w[Two])
    end

    it 'creates edges with metadata' do
      graph = transform.to_graph(diagram)

      expect(graph[:edges].length).to eq(1)

      edge = graph[:edges].first
      expect(edge[:sources]).to eq(['A'])
      expect(edge[:targets]).to eq(['B'])
      expect(edge[:metadata][:arrow_type]).to eq('arrow')
    end

    it 'sets layout options based on direction' do
      graph = transform.to_graph(diagram)

      options = graph[:layoutOptions]
      expect(options['elk.algorithm']).to eq('layered')
      expect(options['elk.direction']).to eq('DOWN')
    end

    it 'converts LR direction to RIGHT layout' do
      diagram.direction = 'LR'
      graph = transform.to_graph(diagram)

      expect(graph[:layoutOptions]['elk.direction']).to eq('RIGHT')
    end

    it 'raises error for invalid diagram' do
      invalid_diagram = Sirena::Diagram::Flowchart.new

      expect do
        transform.to_graph(invalid_diagram)
      end.to raise_error(Sirena::Layout::LayoutError)
    end

    # D10: text measurement must track the theme the renderer actually
    # draws with, not a hardcoded constant -- otherwise a theme with a
    # larger font_size_normal (high_contrast: 16.0 vs default: 14.0) draws
    # text wider than the box sirena measured for it.
    context 'with a theme injected for sizing' do
      let(:diagram) do
        Sirena::Diagram::Flowchart.new(direction: 'TD').tap do |d|
          d.nodes << Sirena::Diagram::FlowchartNode.new(
            id: 'A',
            label: 'Start',
            shape: 'rect'
          )
        end
      end

      def node_width(theme_name)
        themed_transform = described_class.new
        themed_transform.theme = Sirena::Theme::Registry.get(theme_name)
        themed_transform.to_graph(diagram)[:children].first[:width]
      end

      it 'measures a wider node under a theme with a larger font_size_normal' do
        expect(node_width(:high_contrast)).to be > node_width(:default)
      end
    end

    # An edge label draws at font_size_small when the theme sets one
    # (renderer/flowchart.rb#edge_label_font_size), not font_size_normal --
    # so the layout must reserve room against the same font, or an edge
    # label's box is sized for text the renderer never draws.
    context 'with an edge label and a theme whose small and normal sizes differ' do
      let(:diagram) do
        Sirena::Diagram::Flowchart.new(direction: 'TD').tap do |d|
          d.nodes << Sirena::Diagram::FlowchartNode.new(id: 'A', label: 'A')
          d.nodes << Sirena::Diagram::FlowchartNode.new(id: 'B', label: 'B')
          d.edges << Sirena::Diagram::FlowchartEdge.new(
            source_id: 'A', target_id: 'B', arrow_type: 'arrow',
            label: 'edge label text'
          )
        end
      end

      def edge_label_width(typography)
        themed_transform = described_class.new
        themed_transform.theme = Sirena::Theme.new(typography: typography)
        graph = themed_transform.to_graph(diagram)
        graph[:edges].first[:labels].first[:width]
      end

      it 'sizes the edge label at font_size_small, not font_size_normal' do
        small_typography = Sirena::Theme::Typography.new(
          font_size_small: 12.0, font_size_normal: 30.0
        )
        normal_typography = Sirena::Theme::Typography.new(
          font_size_small: 12.0, font_size_normal: 12.0
        )

        expect(edge_label_width(small_typography))
          .to eq(edge_label_width(normal_typography))
      end
    end

    # apply_theme_to_text leaves the SVG element's font_size unset (falling
    # through to Svg::Text::DEFAULT_FONT_SIZE = 16.0) whenever the theme has
    # no typography or no font_size_normal -- so the layout's own fallback
    # has to match 16.0, not a different value, or this exact gap D10 fixes
    # for the has-typography case reopens for the no-typography one.
    context 'with a theme that has no typography at all' do
      it 'measures node text at the SVG render-side default of 16.0' do
        diagram = Sirena::Diagram::Flowchart.new(direction: 'TD').tap do |d|
          d.nodes << Sirena::Diagram::FlowchartNode.new(id: 'A', label: 'A')
        end

        no_typography = described_class.new
        no_typography.theme = Sirena::Theme.new
        explicit_sixteen = described_class.new
        explicit_sixteen.theme = Sirena::Theme.new(
          typography: Sirena::Theme::Typography.new(font_size_normal: 16.0)
        )

        expect(described_class::DEFAULT_FONT_SIZE).to eq(16.0)
        expect(no_typography.to_graph(diagram)[:children].first[:width])
          .to eq(explicit_sixteen.to_graph(diagram)[:children].first[:width])
      end
    end

    # A theme-supplied font size reaches TextMeasurement's box-size
    # arithmetic directly -- an unvalidated non-finite value raises deep in
    # Grid's `.to_i` sizing (FloatDomainError on NaN/Infinity), and a
    # negative one silently produces a smaller-than-fallback label_width
    # (padding alone can mask it in the padded node :width, so this checks
    # the unpadded label measurement directly).
    context 'with a theme carrying an invalid font_size_normal' do
      def label_width_for(font_size_normal)
        themed_transform = described_class.new
        themed_transform.theme = Sirena::Theme.new(
          typography: Sirena::Theme::Typography.new(
            font_size_normal: font_size_normal
          )
        )
        diagram = Sirena::Diagram::Flowchart.new(direction: 'TD').tap do |d|
          d.nodes << Sirena::Diagram::FlowchartNode.new(id: 'A', label: 'A')
        end
        themed_transform.to_graph(diagram)[:children].first[:labels].first[:width]
      end

      it 'falls back to DEFAULT_FONT_SIZE for a negative value' do
        default_label_width = label_width_for(nil)

        expect(label_width_for(-50.0)).to eq(default_label_width)
      end

      it 'does not reach a fuller render for a NaN value' do
        source = "flowchart TD\nA[Start]\nB[End]\nA --> B\n"

        expect do
          Sirena::Engine.new(
            theme: { typography: { font_size_normal: Float::NAN } }
          ).render(source)
        end.not_to raise_error
      end

      it 'does not reach a fuller render for an Infinity value' do
        source = "flowchart TD\nA[Start]\nB[End]\nA --> B\n"

        expect do
          Sirena::Engine.new(
            theme: { typography: { font_size_normal: Float::INFINITY } }
          ).render(source)
        end.not_to raise_error
      end
    end

    # Layout::Base#theme falls back to Theme::Registry.get(:default), and
    # Theme::Registry.clear (public, "useful for testing") empties that
    # registry, so the fallback itself can resolve to nil -- a transform
    # built directly with no theme injected sees exactly this. The renderer
    # already tolerates a nil theme via safe navigation
    # (renderer/base.rb#theme_typography); layout_font_size and
    # edge_label_font_size must match that, not dereference theme directly.
    context 'with no theme registered at all' do
      it 'still measures node text instead of raising' do
        Sirena::Theme::Registry.clear
        diagram = Sirena::Diagram::Flowchart.new(direction: 'TD').tap do |d|
          d.nodes << Sirena::Diagram::FlowchartNode.new(id: 'A', label: 'A')
        end

        expect { transform.to_graph(diagram)[:children].first[:width] }
          .not_to raise_error
      ensure
        Sirena::Theme::Registry.load_builtin_themes
      end
    end
  end
end
