# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Svg::Element do
  # The base attributes and a subclass's declared ones go through one naming
  # rule. When the base list was written out as literal pairs, the SVG names
  # were typed by hand and could not drift; as data they can, so they need a
  # guard the literal never did.
  #
  # Asserted through rendered output rather than the naming helper, which is
  # private: what matters is the attribute an SVG consumer sees.
  describe "base attribute names" do
    subject(:xml) do
      Sirena::Svg::Circle.new.tap do |c|
        c.cx = 1
        c.cy = 2
        c.r = 3
        c.class_name = "node"
        c.stroke_width = "2"
        c.fill_opacity = "0.5"
        c.fill = "red"
      end.to_xml
    end

    it "emits class_name as class, not class-name" do
      # The one reader whose SVG name is not its own hyphenated. Getting this
      # wrong emits class-name, which no SVG consumer honours.
      expect(xml).to include(%( class="node"))
      expect(xml).not_to include("class-name")
    end

    it "hyphenates stroke_width" do
      expect(xml).to include(%( stroke-width="2"))
    end

    it "hyphenates fill_opacity" do
      expect(xml).to include(%( fill-opacity="0.5"))
    end

    it "leaves a single-word name alone" do
      expect(xml).to include(%( fill="red"))
    end

    it "keeps the base attributes in their established order" do
      circle = Sirena::Svg::Circle.new.tap do |c|
        c.id = "a"
        c.class_name = "b"
        c.fill = "red"
        c.stroke = "blue"
      end

      expect(circle.to_xml)
        .to match(/id="a".*class="b".*fill="red".*stroke="blue"/)
    end
  end

  describe "declared subclass attributes" do
    it "hyphenates a declared name too" do
      line = Sirena::Svg::Line.new.tap do |l|
        l.x1 = 0
        l.y1 = 0
        l.x2 = 10
        l.y2 = 10
        l.stroke_dasharray = "5,5"
      end

      expect(line.to_xml).to include(%( stroke-dasharray="5,5"))
    end
  end

  describe "encapsulation" do
    it "keeps the naming helper off the public surface" do
      expect(described_class).not_to respond_to(:svg_name)
    end
  end
end
