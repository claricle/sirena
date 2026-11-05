# frozen_string_literal: true

require "spec_helper"
require_relative "plant_uml_salt/salt_helpers"

# Every number below was read off PlantUML 1.2026.6 (DejaVu Sans, run on
# Linux) on a minimal diagram per group and per `<size>`.
RSpec.describe Sirena::Notation::PlantUMLSalt do
  include SaltHelpers

  def salt(source)
    REXML::Document.new(Sirena.render("@startsalt\n#{source}\n@endsalt"))
  end

  def num(element, *names)
    names.map { |name| element.attributes[name].to_f.round(2) }
  end

  def lines(doc)
    drawn(doc, "line").map { |l| num(l, "x1", "y1", "x2", "y2") }
  end

  def rects(doc)
    drawn(doc, "rect").map { |r| num(r, "x", "y", "width", "height") }
  end

  def texts(doc)
    drawn(doc, "text").map { |t| [t.text, *num(t, "x", "y", "textLength")] }
  end

  def canvas(doc)
    doc.root.attributes["viewBox"]
  end

  describe "{^ titled box" do
    let(:doc) { salt("{^Title\nwide text here\n}") }

    it "puts the title on a white ground over the frame's top edge",
       :aggregate_failures do
      expect(rects(doc)).to include([11.0, 5.0, 26.09, 13.97])
      expect(texts(doc)).to include(["Title", 11.0, 16.14, 26.09])
    end

    it "starts the frame at the middle of the title, cut by row" do
      expect(lines(doc)).to include([5.0, 11.98, 93.98, 11.98],
                                    [5.0, 34.94, 93.98, 34.94],
                                    [5.0, 11.98, 5.0, 34.94])
    end

    it "reserves a title line below the frame, which nothing fills" do
      expect(canvas(doc)).to eq("0 0 99 54")
    end

    it "lets a title wider than the frame widen the canvas" do
      expect(canvas(salt("{^A very long title here\na\n}"))).to eq("0 0 138 54")
    end

    it "cuts the frame at the column gap" do
      doc = salt("{^Group title\na | bb\nccc | d\n}")
      expect(lines(doc)).to include([5.0, 11.98, 26.79, 11.98],
                                    [26.79, 11.98, 44.03, 11.98])
    end

    it "trims the title and reads its markup" do
      expect(texts(salt("{^  Spaced <b>bold</b> title\na\n}")).first(3))
        .to eq([["a", 6.0, 31.11, 7.35], ["Spaced", 11.0, 16.14, 44.19],
                ["bold", 59.0, 16.14, 29.54]])
    end

    it "draws a plain frame when the title is empty" do
      expect(lines(salt("{^\na\n}")).size).to eq(4)
    end

    it "pushes the next row down by the reserved line" do
      doc = salt("{\n{^Title\na\n}\nb\n}")
      expect(texts(doc).find { |t| t[0] == "b" }).to eq(["b", 6.0, 63.04, 7.62])
    end
  end

  describe "{/ tabs" do
    let(:doc) { salt("{\n{/ General | Fonts | Colors }\n{+\ntext\n}\n}") }

    it "sets each tab's text two units in" do
      expect(texts(doc).first(2))
        .to eq([["General", 8.0, 17.14, 47.29], ["Fonts", 70.29, 17.14, 32.81]])
    end

    it "leaves each tab open at the bottom" do
      expect(lines(doc)).to include([6.0, 6.0, 6.0, 19.97],
                                    [6.0, 6.0, 58.29, 6.0],
                                    [58.29, 6.0, 58.29, 19.97],
                                    [58.29, 19.97, 68.29, 19.97])
    end

    it "runs the baseline rule ten units past the last tab" do
      expect(lines(doc)).to include([158.68, 19.97, 168.68, 19.97])
    end

    it "sizes the canvas from the tabs and what follows" do
      expect(canvas(doc)).to eq("0 0 175 44")
    end
  end

  describe "{S scroll bars" do
    it "draws both bars beside and below the frame", :aggregate_failures do
      doc = salt("{S\ntext1\ntext2\n}")
      expect(rects(doc)).to include([42.53, 5.0, 15.0, 31.94],
                                    [5.0, 40.94, 33.53, 15.0])
      expect(canvas(doc)).to eq("0 0 74 72")
    end

    it "draws the vertical bar only for {SI" do
      doc = salt("{SI\ntext1\ntext2\n}")
      expect([rects(doc), canvas(doc)])
        .to eq([[[42.53, 5.0, 15.0, 31.94]], "0 0 74 42"])
    end

    it "draws the horizontal bar only for {S-" do
      doc = salt("{S-\ntext1\ntext2\n}")
      expect([rects(doc), canvas(doc)])
        .to eq([[[5.0, 40.94, 33.53, 15.0]], "0 0 44 72"])
    end

    it "ends each bar with a rule and an arrow", :aggregate_failures do
      doc = salt("{SI\ntext1\ntext2\n}")
      expect(lines(doc)).to include([42.53, 17.0, 57.53, 17.0],
                                    [42.53, 24.94, 57.53, 24.94])
      expect(drawn(doc, "polygon").size).to eq(2)
    end

    it "makes room for the bars in the cell, so the next column clears them" do
      doc = salt("{\n{SI\na\n} | b\nc | d\n}")
      expect(texts(doc)).to include(["b", 47.35, 17.14, 7.62])
    end
  end

  describe "<size:N> markup" do
    it "sets text at the size and sizes the row from it" do
      doc = salt("{\n<size:20>Big\nNormal\n}")
      expect(texts(doc)).to eq([["Big", 6.0, 24.56, 31.97],
                                ["Normal", 6.0, 42.42, 43.63]])
    end

    it "grows a button, field and droplist with the line" do
      doc = salt("{\n[<size:20>Big]\n\"<size:20>Big\"\n^<size:20>Big^\n}")
      expect(rects(doc)).to include([8.5, 8.5, 35.97, 27.28],
                                    [6.0, 67.56, 46.97, 26.28])
    end

    it "hangs runs of mixed size from one baseline" do
      doc = salt("{\na <size:20>b</size> c\n}")
      expect(texts(doc).map { |t| t[2] }).to eq([26.45, 24.56, 26.45])
    end

    it "never sizes a line under ten units" do
      doc = salt("{\n[<size:6>x]\n}")
      expect(rects(doc)).to eq([[8.5, 8.5, 12.0, 14.0]])
    end
  end

  describe "open droplist chain" do
    it "drops the empty choice between ^a^^b^" do
      doc = salt("{\n^a^^b^\nx\n}")
      expect(rects(doc)).to include([6.0, 22.97, 22.0, 12.97])
    end
  end

  describe "{+ frame" do
    it "is cut into a line a row, as the JAR draws it" do
      expect(lines(salt("{+\na\nb\n}")))
        .to include([5.0, 5.0, 5.0, 20.97], [5.0, 20.97, 5.0, 36.94])
    end
  end
end
