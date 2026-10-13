# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Base do
  # The helpers under test are protected; a subclass that widens them is the
  # same route every real renderer takes.
  let(:renderer_class) do
    Class.new(described_class) do
      public :theme_color, :theme_typography, :theme_shape, :theme_spacing,
             :theme_effect, :apply_theme_to_node, :apply_theme_to_edge,
             :apply_theme_to_text, :default_style, :create_path_data,
             :create_document, :calculate_width, :calculate_height,
             :reserved_text_width
    end
  end
  let(:dark) { Sirena::Theme::Registry.get(:dark) }
  let(:renderer) { renderer_class.new(theme: dark) }
  # No theme object at all, and a theme object that answers none of the
  # accessors: both must fall back rather than raise.
  let(:themeless) { renderer_class.new.tap { |r| r.theme = nil } }
  let(:hostile) { renderer_class.new.tap { |r| r.theme = Object.new } }

  def sequence_scene(width, height, view_box)
    Sirena::Layout::Sequence::Scene.new(width:, height:, view_box:)
  end

  describe "#render" do
    it "names the subclass that forgot to implement it" do
      error = /#{Regexp.escape(renderer_class.to_s)} must implement #render/

      expect { renderer_class.new.render(nil) }
        .to raise_error(NotImplementedError, error)
    end
  end

  describe "theme accessors" do
    {
      theme_color: [:node_fill, ->(theme) { theme.colors.node_fill }],
      theme_typography: [
        :font_family, ->(theme) { theme.typography.font_family }
      ],
      theme_shape: [:stroke_width, ->(theme) { theme.shapes.stroke_width }],
      theme_spacing: [
        :rank_spacing, ->(theme) { theme.spacing.rank_spacing }
      ],
      theme_effect: [:shadow_blur, ->(theme) { theme.effects.shadow_blur }],
    }.each do |accessor, (property, section)|
      it "#{accessor} reads from its own section of the active theme" do
        expect(renderer.public_send(accessor, property))
          .to eq(section.call(dark))
      end

      it "#{accessor} is nil for an unknown property" do
        expect(renderer.public_send(accessor, :no_such_property)).to be_nil
      end

      it "#{accessor} is nil with no theme" do
        expect(themeless.public_send(accessor, property)).to be_nil
      end

      it "#{accessor} is nil for a theme without the section" do
        expect(hostile.public_send(accessor, property)).to be_nil
      end
    end

    it "reads a value that differs from the default theme's" do
      expect(dark.colors.node_fill)
        .not_to eq(Sirena::Theme::Registry.get(:default).colors.node_fill)
    end
  end

  describe "apply_theme_to_*" do
    it "paints a node with the theme fill, stroke and stroke width" do
      node = Sirena::Svg::Rect.new.tap { |e| renderer.apply_theme_to_node(e) }

      expect([node.fill, node.stroke, node.stroke_width]).to eq(
        [dark.colors.node_fill, dark.colors.node_stroke,
         dark.shapes.stroke_width.to_s],
      )
    end

    it "paints an edge with the theme stroke and stroke width, " \
       "leaving fill alone" do
      edge = Sirena::Svg::Path.new.tap { |e| renderer.apply_theme_to_edge(e) }

      expect([edge.stroke, edge.stroke_width, edge.fill]).to eq(
        [dark.colors.edge_stroke, dark.shapes.stroke_width.to_s, nil],
      )
    end

    it "paints text with the theme colour, family and size" do
      text = Sirena::Svg::Text.new.tap { |e| renderer.apply_theme_to_text(e) }

      expect([text.fill, text.font_family, text.font_size]).to eq(
        [dark.colors.label_text, dark.typography.font_family,
         dark.typography.font_size_normal.to_s],
      )
    end

    context "when the theme has nothing to say" do
      it "leaves a node untouched" do
        node = Sirena::Svg::Rect.new.tap { |e| hostile.apply_theme_to_node(e) }

        expect([node.fill, node.stroke, node.stroke_width]).to all(be_nil)
      end

      it "leaves an edge untouched" do
        edge = Sirena::Svg::Path.new.tap { |e| hostile.apply_theme_to_edge(e) }

        expect([edge.stroke, edge.stroke_width]).to all(be_nil)
      end

      it "leaves text untouched" do
        text = Sirena::Svg::Text.new.tap { |e| hostile.apply_theme_to_text(e) }

        expect([text.fill, text.font_family, text.font_size]).to all(be_nil)
      end
    end
  end

  describe "#default_style" do
    it "takes node colours and stroke width from the theme" do
      expect(renderer.default_style(:node).to_css).to eq(
        "fill:#{dark.colors.node_fill};stroke:#{dark.colors.node_stroke};" \
        "stroke-width:#{dark.shapes.stroke_width}",
      )
    end

    it "draws an edge unfilled, with the theme stroke" do
      expect(renderer.default_style(:edge).to_css).to eq(
        "fill:none;stroke:#{dark.colors.edge_stroke};" \
        "stroke-width:#{dark.shapes.stroke_width}",
      )
    end

    it "centres text and takes colour, family and size from the theme" do
      expect(renderer.default_style(:text).to_css).to eq(
        "fill:#{dark.colors.label_text};" \
        "font-family:#{dark.typography.font_family};" \
        "font-size:#{dark.typography.font_size_normal};text-anchor:middle",
      )
    end

    context "when the theme is absent" do
      it "falls back to a white node with a black stroke" do
        expect(themeless.default_style(:node).to_css)
          .to eq("fill:#ffffff;stroke:#000000;stroke-width:2.0")
      end

      it "falls back to an unfilled edge with a black stroke" do
        expect(themeless.default_style(:edge).to_css)
          .to eq("fill:none;stroke:#000000;stroke-width:2.0")
      end

      it "falls back to black centred Arial text" do
        expect(themeless.default_style(:text).to_css).to eq(
          "fill:#000000;font-family:Arial, sans-serif;font-size:14.0;" \
          "text-anchor:middle",
        )
      end
    end

    it "is empty for an element type it does not know" do
      expect(renderer.default_style(:cloud).to_css).to eq("")
    end
  end

  describe "#create_path_data" do
    it "runs a straight line when there are no bend points" do
      expect(renderer.create_path_data({ x: 1, y: 2 }, { x: 9, y: 8 }))
        .to eq("M 1 2 L 9 8")
    end

    it "visits the bend points in order between start and end" do
      bends = [{ x: 3, y: 4 }, { x: 5, y: 6 }]

      expect(renderer.create_path_data({ x: 1, y: 2 }, { x: 9, y: 8 }, bends))
        .to eq("M 1 2 L 3 4 L 5 6 L 9 8")
    end
  end

  describe "document sizing" do
    it "defaults to 800x600" do
      expect([renderer.calculate_width(nil), renderer.calculate_height(nil)])
        .to eq([800, 600])
    end

    it "uses the final Scene dimensions and starts the viewBox at zero" do
      scene = sequence_scene(810, 610, "0 0 810 610")
      doc = renderer.create_document(scene)

      expect([doc.width, doc.height, doc.view_box, doc.overflow])
        .to eq([810, 610, "0 0 810 610", nil])
    end

    it "keeps no horizontal offset state when sizing a Scene" do
      renderer.create_document(sequence_scene(810, 610, "0 0 810 610"))

      expect(renderer.instance_variable_defined?(:@offset_x)).to be(false)
    end

    it "keeps fractional dimensions in the zero-origin viewBox" do
      scene = sequence_scene(100.5, 50.25, "0 0 100.5 50.25")

      expect([scene.width, scene.height,
              renderer.create_document(scene).view_box])
        .to eq([100.5, 50.25, "0 0 100.5 50.25"])
    end

    it "keeps no vertical offset state when sizing a fractional Scene" do
      renderer.create_document(
        sequence_scene(100.5, 50.25, "0 0 100.5 50.25"),
      )

      expect(renderer.instance_variable_defined?(:@offset_y)).to be(false)
    end

    it "keeps matching dimension spelling but replaces a non-zero origin" do
      scene = sequence_scene(100, 50, "5 6 100.0 50.0")

      expect(renderer.create_document(scene).view_box).to eq("0 0 100.0 50.0")
    end

    it "ignores stale viewBox dimensions" do
      scene = sequence_scene(100, 50, "5 6 70 80")

      expect([renderer.create_document(scene).width,
              renderer.create_document(scene).view_box])
        .to eq([100, "0 0 100 50"])
    end

    it "leaves the overflow attribute unset by default" do
      scene = sequence_scene(100, 50, "0 0 100 50")

      expect(renderer.create_document(scene).overflow).to be_nil
    end

    it "sets the overflow attribute when asked" do
      scene = sequence_scene(100, 50, "0 0 100 50")

      expect(renderer.create_document(scene, overflow: "hidden").overflow)
        .to eq("hidden")
    end
  end

  describe "#initialize" do
    it "uses the default theme when none is given" do
      expect(renderer_class.new.theme).to equal(Sirena::Theme::Registry.get(:default))
    end
  end

  describe "#reserved_text_width" do
    it "is the measured width plus 20 percent for a substituted font" do
      measured = Sirena::TextMeasurement.measure("Hello", font_size: 14)[:width]

      expect(renderer.reserved_text_width("Hello", 14))
        .to be_within(0.001).of(measured * 1.2)
    end
  end
end
