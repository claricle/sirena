# frozen_string_literal: true

require "spec_helper"
require_relative "plant_uml_salt/salt_helpers"

# Every number below was read off PlantUML 1.2026.6 on a minimal diagram
# per widget and per block modifier. Text widths are measured with the
# same estimator the layout uses, so only the widget geometry is pinned.
RSpec.describe Sirena::Notation::PlantUMLSalt do
  include SaltHelpers

  def render(body)
    REXML::Document.new(Sirena.render("@startsalt\n{\n#{body}\n}\n@endsalt"))
  end

  def elements(doc, name)
    doc.get_elements("//#{name}")
  end

  def numbers(element, *names)
    names.map { |name| element.attributes[name].to_f.round(2) }
  end

  def width_of(text)
    Sirena::TextMeasurement.measure(text, font_size: 12)[:width]
  end

  def segments(doc)
    elements(doc, "line").map { |l| numbers(l, "x1", "y1", "x2", "y2") }
  end

  describe "rows and cells" do
    let(:doc) { render("a | b\nc | d") }
    let(:ys) do
      elements(doc, "text").map { |t| t.attributes["y"].to_f.round(2) }
    end

    it "sets rows 14.13 tall with a two-pixel gap" do
      expect(ys).to eq([17.6, 17.6, 33.73, 33.73])
    end

    it "separates columns by a two-pixel gap" do
      xs = elements(doc, "text").map { |t| t.attributes["x"].to_f.round(2) }
      expect(xs.first(2)).to eq([6.0, (6 + width_of("a") + 2).round(2)])
    end

    it "pads a block one pixel and its canvas five" do
      left = 6 + width_of("a") + 2 + width_of("b") + 1
      expect(doc.root.attributes["viewBox"])
        .to eq("0 0 #{(left + 5).ceil} 43")
    end

    it "pads a nested block one pixel inside its cell" do
      xs = elements(render("x\n{ a | b } | c"), "text")
        .map { |t| t.attributes["x"].to_f }
      expect(xs[1]).to eq(7.0)
    end

    it "stacks several top-level lines as rows of one block" do
      texts = svg_texts(Sirena.render("@startsalt\nx\n{ a } | c\ny\n"))
      expect(texts).to eq(%w[x a c y])
    end

    it "closes an empty block mid-line" do
      texts = svg_texts(Sirena.render("@startsalt\n{\n{+ } | c\n}"))
      expect(texts).to eq(%w[c])
    end

    it "closes a block mid-line and keeps the cells after it" do
      texts = svg_texts(Sirena.render("@startsalt\n{\n{# a | b } | c\n}"))
      expect(texts).to eq(%w[a b c])
    end
  end

  describe "block rules" do
    def render_block(modifier)
      REXML::Document.new(
        Sirena.render("@startsalt\n{#{modifier}\na | b\nc | d\n}\n@endsalt"),
      )
    end

    let(:wide) { 6 + width_of("a") + 2 + width_of("b") + 1 }
    let(:cut) { (6 + width_of("a") + 1).round(2) }

    it "draws {- rules above, between and below the rows" do
      expect(segments(render_block("-")).map { |l| l[1] }.sort)
        .to eq([5.0, 21.13, 37.27])
    end

    it "spans each {- rule from edge to edge" do
      expect(segments(render_block("-")).map { |l| [l[0], l[2]] }.uniq)
        .to eq([[5.0, wide.round(2)]])
    end

    it "draws {! bars left of, between and right of the columns" do
      expect(segments(render_block("!")).map(&:first))
        .to eq([5.0, cut, wide.round(2)])
    end

    it "runs each {! bar the full height" do
      expect(segments(render_block("!")).map { |l| [l[1], l[3]] }.uniq)
        .to eq([[5.0, 37.27]])
    end

    it "draws {# both rules and no frame" do
      doc = render_block("#")
      expect([segments(doc).size, elements(doc, "rect").size]).to eq([6, 0])
    end

    it "draws {+ as one one-pixel frame on the block's edge" do
      rect = elements(render_block("+"), "rect").first
      expect([numbers(rect, "x", "y", "height", "stroke-width"),
              rect.attributes["fill"]])
        .to eq([[5.0, 5.0, 32.27, 1.0], "none"])
    end

    it "draws a plain block with no rule or frame" do
      doc = render_block("")
      expect(elements(doc, "line") + elements(doc, "rect")).to be_empty
    end
  end

  describe "button" do
    let(:doc) { render("[OK]\n[a much longer label]") }
    let(:rects) { elements(doc, "rect") }

    it "is a rounded #EEEEEE box with a 2.5 stroke inset 2.5" do
      first = rects.first
      expect([numbers(first, "x", "y", "height", "rx", "stroke-width"),
              first.attributes["fill"]])
        .to eq([[8.5, 8.5, 18.13, 5.0, 2.5], "#EEEEEE"])
    end

    it "is four wider than the label, or than eight a character" do
      expect([numbers(rects[0], "width"), numbers(rects[1], "width")])
        .to eq([[(width_of("OK") + 4).round(2)],
                [[width_of("a much longer label"), 19 * 8.0].max + 4]])
    end

    it "centres the label in the box" do
      text = elements(doc, "text").first
      room = ([width_of("OK"), 16.0].max - width_of("OK")) / 2
      expect(text.attributes["x"].to_f.round(2)).to eq((10.5 + room).round(2))
    end

    it "takes 23.13 of row height" do
      ys = elements(render("[A]\nb"), "text").map { |t| t.attributes["y"].to_f }
      expect(ys.last.round(2)).to eq((6 + 23.13 + 2 + 11.6).round(2))
    end
  end

  describe "text field" do
    let(:doc) { render("\"name\"") }

    it "is an underline with a tick at each end" do
      right = (7 + [width_of("name"), 32.0].max + 3).round(2)
      expect(segments(doc)).to include([7.0, 20.13, right, 20.13],
                                       [7.0, 17.13, 7.0, 19.13],
                                       [right, 17.13, right, 19.13])
    end

    it "sets its text three pixels in" do
      expect(elements(doc, "text").first.attributes["x"]).to eq("9.0")
    end

    it "draws no box" do
      expect(elements(doc, "rect")).to be_empty
    end
  end

  describe "droplist" do
    let(:doc) { render("^pick^") }
    let(:span) { [width_of("pick"), 32.0].max }

    it "is a #EEEEEE box 15 wider than its span" do
      rect = elements(doc, "rect").first
      expect([numbers(rect, "x", "y", "height", "width", "stroke-width"),
              rect.attributes["fill"]])
        .to eq([[6.0, 6.0, 17.13, (span + 15).round(2), 1.0], "#EEEEEE"])
    end

    it "splits the arrow off with a bar" do
      expect(segments(doc).first[0]).to eq((6 + span + 4).round(2))
    end

    it "points a black triangle down after the bar" do
      polygon = elements(doc, "polygon").first
      near, far, mid = [7, 13, 10].map { |dx| (6 + span + dx).round(4) }
      expect([polygon.attributes["fill"], polygon.attributes["points"]])
        .to eq(["#000000", "#{near},12.0 #{far},12.0 #{mid},18.1328"])
    end
  end

  describe "checkbox" do
    let(:doc) { render("[] off\n[X] on") }

    it "is a 10 pixel unfilled square with a 1.5 stroke" do
      rect = elements(doc, "rect").first
      expect([numbers(rect, "x", "y", "width", "height", "stroke-width"),
              rect.attributes["fill"]])
        .to eq([[8.0, 8.07, 10.0, 10.0, 1.5], "none"])
    end

    it "adds a black tick when checked" do
      expect(elements(doc, "polygon").first.attributes["points"])
        .to eq("9.0,28.1328 12.0,31.1328 19.0,22.1328 12.0,29.1328")
    end

    it "sets the label twenty pixels in" do
      expect(elements(doc, "text").first.attributes["x"]).to eq("26.0")
    end
  end

  describe "radio" do
    let(:doc) { render("() off\n(X) on") }
    let(:circles) { elements(doc, "ellipse") }

    it "is a radius-5 ring with a 1.5 stroke" do
      expect([numbers(circles.first, "cx", "cy", "rx", "stroke-width"),
              circles.first.attributes["fill"]])
        .to eq([[13.0, 13.07, 5.0, 1.5], "none"])
    end

    it "adds a radius-2 black dot when checked" do
      dot = circles.last
      expect([numbers(dot, "rx"), dot.attributes["fill"], circles.size])
        .to eq([[2.0], "#000000", 3])
    end
  end

  describe "an empty checkbox label" do
    it "still reserves the width of a space" do
      xs = elements(render("[] | b"), "text").map { |t| t.attributes["x"].to_f }
      expect(xs.last.round(2)).to eq((6 + 20 + width_of(" ") + 2).round(2))
    end
  end
end
