# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::SequenceRenderer do
  # These assertions exist because the corpus sweep cannot make them. It
  # checks that a well-formed SVG comes out, so an arrow drawn with the
  # wrong line style or a head mermaid does not draw still scores a pass.
  #
  # Every expectation below is taken from mmdc 11.12.0's own output for the
  # same source: messageLine0/messageLine1 for the line style, and the
  # presence of marker-end / marker-start for the heads.
  def message_group(arrow, source = nil)
    xml = Sirena.render(source || "sequenceDiagram\n    A#{arrow}B: m\n")
    xml[%r{<g id="message-0".*?</g>}m]
  end

  def arrowheads(arrow)
    message_group(arrow).scan("<polygon").size
  end

  def dashed?(arrow)
    message_group(arrow).include?("stroke-dasharray")
  end

  describe "head style" do
    it "draws no arrowhead on ->" do
      expect(arrowheads("->")).to eq(0)
    end

    it "draws no arrowhead on -->" do
      expect(arrowheads("-->")).to eq(0)
    end

    it "draws one arrowhead on ->>" do
      expect(arrowheads("->>")).to eq(1)
    end

    it "draws an arrowhead at both ends of <<->>, one per end" do
      # A count alone would pass with two heads stacked at the same end.
      tips = message_group("<<->>").scan(/<polygon[^>]*points="(\d+),/).flatten

      expect(tips).to contain_exactly("80", "220")
    end

    it "draws a stroked cross on -x, not a filled head" do
      group = message_group("-x")

      # Two strokes that cross, and no polygon: mermaid's crosshead is
      # stroke-only (fill="none"), unlike every other head it draws.
      expect(group.scan("<polygon").size).to eq(0)
      expect(group.scan("<line").size).to eq(3)

      # The two strokes straddle the tip rather than stopping at it, and
      # the shaft runs its full length because a cross takes no inset.
      strokes = group.scan(/<line[^>]*>/).drop(1)
      expect(strokes.map { |l| l[/x1="([\d.]+)"/, 1] }).to all(eq("216.0"))
      expect(strokes.map { |l| l[/x2="([\d.]+)"/, 1] }).to all(eq("224.0"))
    end

    it "draws a filled concave chevron on -)" do
      # mermaid's filled-head marker, path "M 18,7 L9,13 L14,7 L9,1 Z" — a
      # filled four-point head with a notch, not two open strokes.
      points = message_group("-)")[/<polygon[^>]*points="([^"]*)"/, 1]

      expect(points.split.size).to eq(4)
      expect(points).to eq("220,120 212,116 215.2,120 212,124")
    end
  end

  describe "line style" do
    it "draws -> solid" do
      expect(dashed?("->")).to be(false)
    end

    it "draws --> dashed" do
      expect(dashed?("-->")).to be(true)
    end

    it "draws ->> solid" do
      expect(dashed?("->>")).to be(false)
    end

    it "draws -->> dashed" do
      expect(dashed?("-->>")).to be(true)
    end

    it "draws <<-->> dashed with both heads" do
      expect(dashed?("<<-->>")).to be(true)
      expect(arrowheads("<<-->>")).to eq(2)
    end
  end

  describe "line inset" do
    def message_line(arrow, axis, source = nil)
      line = message_group(arrow, source)[/<line[^>]*>/]
      line[/#{axis}="([\d.]+)"/, 1].to_f
    end

    it "shortens the line at the source only when that end carries a head" do
      expect(message_line("<<->>", "x1")).to be > message_line("->>", "x1")
    end

    it "does not shorten the line when there is no head" do
      expect(message_line("->", "x2")).to be > message_line("->>", "x2")
    end

    it "insets towards the head on a right-to-left message" do
      # Unsigned, this ran the shaft past its own head: B<<->>A started at
      # 228 while the source head occupied 212 to 220.
      rtl = "sequenceDiagram\n    participant A\n    participant B\n" \
            "    B<<->>A: m\n"

      expect(message_line("<<->>", "x1", rtl)).to eq(212.0)
      expect(message_line("<<->>", "x2", rtl)).to eq(88.0)
    end
  end
end
