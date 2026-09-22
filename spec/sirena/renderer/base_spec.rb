# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Renderer::Base do
  # The helpers under test are protected; a subclass that widens them is the
  # same route every real renderer takes.
  let(:renderer_class) do
    Class.new(described_class) do
      public :theme_color, :theme_typography, :theme_shape, :theme_spacing,
             :theme_effect, :apply_theme_to_node, :apply_theme_to_edge,
             :apply_theme_to_text, :default_style, :create_path_data,
             :create_document, :calculate_width, :calculate_height
    end
  end
  let(:dark) { Sirena::Theme::Registry.get(:dark) }
  let(:renderer) { renderer_class.new(theme: dark) }
  # No theme object at all, and a theme object that answers none of the
  # accessors: both must fall back rather than raise.
  let(:themeless) { renderer_class.new.tap { |r| r.theme = nil } }
  let(:hostile) { renderer_class.new.tap { |r| r.theme = Object.new } }

  describe '#render' do
    it 'names the subclass that forgot to implement it' do
      expect { renderer_class.new.render(nil) }
        .to raise_error(NotImplementedError, /#{Regexp.escape(renderer_class.to_s)} must implement #render/)
    end
  end

  describe 'theme accessors' do
    it 'reads the value from the active theme, not the default one' do
      expect(renderer.theme_color(:node_fill)).to eq(dark.colors.node_fill)
      expect(dark.colors.node_fill).not_to eq(Sirena::Theme::Registry.get(:default).colors.node_fill)
    end

    it 'reads each accessor from its own section of the theme' do
      expect([
               renderer.theme_color(:node_fill), renderer.theme_typography(:font_family),
               renderer.theme_shape(:stroke_width), renderer.theme_spacing(:rank_spacing),
               renderer.theme_effect(:shadow_blur)
             ]).to eq([
                        dark.colors.node_fill, dark.typography.font_family,
                        dark.shapes.stroke_width, dark.spacing.rank_spacing,
                        dark.effects.shadow_blur
                      ])
    end

    {
      theme_color: :node_fill,
      theme_typography: :font_family,
      theme_shape: :stroke_width,
      theme_spacing: :rank_spacing,
      theme_effect: :shadow_blur
    }.each do |accessor, property|
      it "#{accessor} is nil for an unknown property, no theme, or a theme without the section" do
        expect(renderer.public_send(accessor, :no_such_property)).to be_nil
        expect(themeless.public_send(accessor, property)).to be_nil
        expect(hostile.public_send(accessor, property)).to be_nil
      end
    end
  end

  describe 'apply_theme_to_*' do
    it 'paints a node with the theme fill, stroke and stroke width' do
      element = Sirena::Svg::Rect.new
      renderer.apply_theme_to_node(element)

      expect([element.fill, element.stroke, element.stroke_width]).to eq(
        [dark.colors.node_fill, dark.colors.node_stroke,
         dark.shapes.stroke_width.to_s]
      )
    end

    it 'paints an edge with the theme stroke and stroke width, leaving fill alone' do
      element = Sirena::Svg::Path.new
      renderer.apply_theme_to_edge(element)

      expect([element.stroke, element.stroke_width, element.fill]).to eq(
        [dark.colors.edge_stroke, dark.shapes.stroke_width.to_s, nil]
      )
    end

    it 'paints text with the theme colour, family and size' do
      element = Sirena::Svg::Text.new
      renderer.apply_theme_to_text(element)

      expect([element.fill, element.font_family, element.font_size]).to eq(
        [dark.colors.label_text, dark.typography.font_family,
         dark.typography.font_size_normal.to_s]
      )
    end

    it 'leaves every element untouched when the theme has nothing to say' do
      node = Sirena::Svg::Rect.new
      edge = Sirena::Svg::Path.new
      text = Sirena::Svg::Text.new
      hostile.apply_theme_to_node(node)
      hostile.apply_theme_to_edge(edge)
      hostile.apply_theme_to_text(text)

      expect([node.fill, node.stroke, node.stroke_width,
              edge.stroke, edge.stroke_width,
              text.fill, text.font_family, text.font_size]).to all(be_nil)
    end
  end

  describe '#default_style' do
    it 'takes node colours and stroke width from the theme' do
      css = renderer.default_style(:node).to_css

      expect(css).to eq(
        "fill:#{dark.colors.node_fill};stroke:#{dark.colors.node_stroke};" \
        "stroke-width:#{dark.shapes.stroke_width}"
      )
    end

    it 'draws an edge unfilled, with the theme stroke' do
      css = renderer.default_style(:edge).to_css

      expect(css).to eq(
        "fill:none;stroke:#{dark.colors.edge_stroke};" \
        "stroke-width:#{dark.shapes.stroke_width}"
      )
    end

    it 'centres text and takes colour, family and size from the theme' do
      css = renderer.default_style(:text).to_css

      expect(css).to eq(
        "fill:#{dark.colors.label_text};" \
        "font-family:#{dark.typography.font_family};" \
        "font-size:#{dark.typography.font_size_normal};text-anchor:middle"
      )
    end

    it 'falls back to plain black-on-white values when the theme is absent' do
      expect(themeless.default_style(:node).to_css)
        .to eq('fill:#ffffff;stroke:#000000;stroke-width:2.0')
      expect(themeless.default_style(:edge).to_css)
        .to eq('fill:none;stroke:#000000;stroke-width:2.0')
      expect(themeless.default_style(:text).to_css).to eq(
        'fill:#000000;font-family:Arial, sans-serif;font-size:14.0;' \
        'text-anchor:middle'
      )
    end

    it 'is empty for an element type it does not know' do
      expect(renderer.default_style(:cloud).to_css).to eq('')
    end
  end

  describe '#create_path_data' do
    it 'runs a straight line when there are no bend points' do
      expect(renderer.create_path_data({ x: 1, y: 2 }, { x: 9, y: 8 })).to eq('M 1 2 L 9 8')
    end

    it 'visits the bend points in order between start and end' do
      bends = [{ x: 3, y: 4 }, { x: 5, y: 6 }]

      expect(renderer.create_path_data({ x: 1, y: 2 }, { x: 9, y: 8 }, bends))
        .to eq('M 1 2 L 3 4 L 5 6 L 9 8')
    end
  end

  describe 'document sizing' do
    it 'defaults to 800x600' do
      expect([renderer.calculate_width(nil), renderer.calculate_height(nil)])
        .to eq([800, 600])
    end

    it 'grows each dimension by twice the padding and starts the viewBox at zero' do
      doc = renderer.create_document(nil, padding: 5)

      expect([doc.width, doc.height, doc.view_box])
        .to eq([810, 610, '0 0 810 610'])
    end

    it 'pads by 20 when no padding is given' do
      expect(renderer.create_document(nil).view_box).to eq('0 0 840 640')
    end

    it 'sets the overflow attribute only when asked' do
      expect(renderer.create_document(nil).overflow).to be_nil
      expect(renderer.create_document(nil, overflow: 'hidden').overflow)
        .to eq('hidden')
    end
  end

  describe '#initialize' do
    it 'uses the default theme when none is given' do
      expect(renderer_class.new.theme).to equal(Sirena::Theme::Registry.get(:default))
    end
  end
end
