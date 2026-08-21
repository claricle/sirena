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
    # Counting polygons alone let a cross — which is drawn with lines —
    # be added to a "headless" arrow without failing anything.
    %w[-> -->].each do |arrow|
      it "draws nothing but the shaft on #{arrow}" do
        group = message_group(arrow)

        expect(group.scan("<polygon").size).to eq(0)
        expect(group.scan("<line").size).to eq(1)
        expect(group[/<line[^>]*>/]).to include('x2="220.0"')
      end
    end

    it "draws one arrowhead, at the target, on ->>" do
      group = message_group("->>")

      expect(group.scan("<polygon").size).to eq(1)
      expect(group[/<polygon[^>]*points="([^"]*)"/, 1])
        .to eq("220,120 212,116 212,124")
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
      shaft, *strokes = group.scan(/<line[^>]*>/)
      expect(shaft).to include('x1="80.0"').and include('x2="220.0"')
      expect(strokes.map { |l| l[/x1="[\d.]+" y1="[\d.]+" x2="[\d.]+" y2="[\d.]+"/] })
        .to contain_exactly('x1="216.0" y1="116.0" x2="224.0" y2="124.0"',
                            'x1="216.0" y1="124.0" x2="224.0" y2="116.0"')
      # Stroke-only is the point: mermaid's crosshead sets fill="none".
      expect(strokes).to all(include('stroke="#000000"'))
      expect(strokes).to all(include('stroke-width="2"'))
    end

    it "draws a filled concave chevron on -)" do
      # mermaid's filled-head marker, path "M 18,7 L9,13 L14,7 L9,1 Z" — a
      # filled four-point head with a notch, not two open strokes. The fill
      # is the point: an unfilled polygon of the same shape looks wrong.
      polygon = message_group("-)")[/<polygon[^>]*>/]

      expect(polygon).to include('fill="#000000"')
      expect(polygon[/points="([^"]*)"/, 1]).to eq("220,120 212,116 215.2,120 212,124")
    end

    it "draws one barb below the line on -|/" do
      # mermaid's solidBottomArrowHead: a single barb, not a full head.
      polygon = message_group("-|/")[/<polygon[^>]*>/]

      expect(polygon).to include('fill="#000000"')
      expect(polygon[/points="([^"]*)"/, 1]).to eq("220,120 212,124 212,120")
    end

    it "draws one barb above the line on -|\\" do
      polygon = message_group("-|\\")[/<polygon[^>]*>/]

      expect(polygon[/points="([^"]*)"/, 1]).to eq("220,120 212,116 212,120")
    end

    # mermaid's stickBottomArrowHead is `M 0 7 L 7 0` with fill="none" —
    # one stroke, where the solid variant is a filled wedge. Drawing both
    # as polygons made `-//` and `-|/` the same picture.
    {
      "-//" => 'x1="220.0" y1="120.0" x2="212.0" y2="124.0"',
      "-\\\\" => 'x1="220.0" y1="120.0" x2="212.0" y2="116.0"'
    }.each do |arrow, stroke|
      it "draws one unfilled stroke on #{arrow}" do
        group = message_group(arrow)

        expect(group.scan("<polygon").size).to eq(0)
        expect(group.scan(/<line[^>]*>/).last).to include(stroke)
      end
    end

    # The reversed spellings put the head on the source end. mermaid marks
    # every head `orient="auto-start-reverse"`, so the same marker at the
    # start is rotated 180 degrees — a "bottom" head sits above the line.
    it "draws the barb of /|- at the source, flipped" do
      group = message_group("/|-")

      expect(group[/<polygon[^>]*points="([^"]*)"/, 1])
        .to eq("80,120 88,116 88,120")
    end

    it "draws the stroke of //- at the source, flipped" do
      group = message_group("//-")

      expect(group.scan("<polygon").size).to eq(0)
      expect(group.scan(/<line[^>]*>/).last)
        .to include('x1="80.0" y1="120.0" x2="88.0" y2="116.0"')
    end

    it "insets the shaft at the end that carries a filled head" do
      # A wedge occupies the last few pixels of the shaft, so the shaft
      # stops short of it — at whichever end it is. Insetting the target
      # end regardless drew /|- through its own barb.
      expect(message_group("/|-")[/<line[^>]*>/])
        .to include('x1="88.0"').and include('x2="220.0"')
    end

    it "runs the shaft up to the tip under a concave head" do
      # The chevron of `-)` meets the centreline at its notch, not at its
      # back edge, so insetting the shaft left a gap between 212 and 215.2.
      headless = message_group("->")[/<line[^>]*>/]

      expect(message_group("-)")[/<line[^>]*>/]).to eq(headless)
    end

    it "runs the shaft full length under a stick head" do
      # A stick is one diagonal stroke from the tip, so it covers none of
      # the shaft. Insetting for it left an eight-pixel gap where mermaid
      # attaches the marker and draws none.
      headless = message_group("->")[/<line[^>]*>/]

      expect(message_group("//-")[/<line[^>]*>/])
        .to include('x1="80.0"').and include('x2="220.0"')
      expect(message_group("-//")[/<line[^>]*>/]).to eq(headless)
    end

    # Which way a head is rotated follows the direction from the shaft to
    # the tip, not which end of the line the head sits on. Keying on the
    # end drew every right-to-left message as the mirror of mmdc's.
    describe "a right-to-left message" do
      def rtl_group(arrow)
        source = "sequenceDiagram\n    participant A\n    participant B\n    " \
                 "B#{arrow}A: m\n"
        message_group(arrow, source)
      end

      it "flips the target barb of -|/ to the other side" do
        expect(rtl_group("-|/")[/<polygon[^>]*points="([^"]*)"/, 1])
          .to eq("80,120 88,116 88,120")
      end

      it "draws the source barb of /|- below, as left-to-right draws it" do
        expect(rtl_group("/|-")[/<polygon[^>]*points="([^"]*)"/, 1])
          .to eq("220,120 212,124 212,120")
      end
    end

    it "mirrors the chevron on a right-to-left message" do
      rtl = <<~MERMAID
        sequenceDiagram
            participant A
            participant B
            B-)A: m
      MERMAID
      polygon = message_group("-)", rtl)[/<polygon[^>]*>/]

      expect(polygon[/points="([^"]*)"/, 1]).to eq("80,120 88,116 84.8,120 88,124")
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

    it "draws <<-->> dashed with one head at each end" do
      tips = message_group("<<-->>").scan(/<polygon[^>]*points="(\d+),/).flatten

      expect(dashed?("<<-->>")).to be(true)
      expect(tips).to contain_exactly("80", "220")
    end
  end

  describe "a participant messaging itself" do
    # A straight shaft has no horizontal run here, so it collapsed to
    # nothing: A->A drew neither a line nor a head. mermaid loops back to
    # the same lifeline.
    def self_group(arrow)
      xml = Sirena.render(
        "sequenceDiagram\n    participant A\n    A#{arrow}A: self\n"
      )
      xml[%r{<g id="message-0".*?</g>}m]
    end

    it "draws a loop for a headless self-message" do
      group = self_group("->")

      # Reaching right, not left: the loop must not cross the lifeline into
      # the previous participant's column.
      expect(group[/<path[^>]*d="([^"]*)"/, 1])
        .to eq("M 80,110 C 136,110 136,130 80,130")
      expect(group.scan("<polygon").size).to eq(0)
    end

    it "draws a loop and one head at its return for ->>" do
      group = self_group("->>")

      expect(group.scan("<polygon").size).to eq(1)
      expect(group[/<polygon[^>]*points="([^"]*)"/, 1])
        .to eq("80,130 88,126 88,134")
    end

    it "draws a head at each end of a bidirectional self-message" do
      # mmdc emits both a marker-start and a marker-end here.
      group = self_group("<<->>")
      tips = group.scan(/<polygon[^>]*points="[\d.]+,([\d.]+)/).flatten

      expect(tips).to contain_exactly("110", "130")
    end

    it "lifts the label clear of the loop" do
      # The loop reaches half its height above the message line, so the
      # ordinary offset put the text baseline on the loop's top edge.
      group = self_group("->>")
      label_y = group[/<text[^>]*y="([\d.]+)"/, 1].to_f
      loop_top = group[/<path[^>]*d="M [\d.]+,([\d.]+)/, 1].to_f

      expect(label_y).to be < loop_top
    end

    it "dashes the loop for a dotted self-message" do
      expect(self_group("-->")).to include("stroke-dasharray")
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
      rtl = <<~MERMAID
        sequenceDiagram
            participant A
            participant B
            B<<->>A: m
      MERMAID

      expect(message_line("<<->>", "x1", rtl)).to eq(212.0)
      expect(message_line("<<->>", "x2", rtl)).to eq(88.0)
    end
  end
end
