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
  def message_group(arrow)
    xml = Sirena.render("sequenceDiagram\n    A#{arrow}B: m\n")
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

    it "draws an arrowhead at both ends of <<->>" do
      expect(arrowheads("<<->>")).to eq(2)
    end

    it "draws a cross rather than an arrowhead on -x" do
      group = message_group("-x")

      expect(group.scan("<polygon").size).to eq(0)
      expect(group.scan("<line").size).to eq(3)
    end

    it "draws an open head rather than a filled one on -)" do
      group = message_group("-)")

      expect(group.scan("<polygon").size).to eq(0)
      expect(group.scan("<line").size).to eq(3)
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
    def message_line(arrow, axis)
      line = message_group(arrow)[/<line[^>]*>/]
      line[/#{axis}="([\d.]+)"/, 1].to_f
    end

    it "shortens the line at the source only when that end carries a head" do
      expect(message_line("<<->>", "x1")).to be > message_line("->>", "x1")
    end

    it "does not shorten the line when there is no head" do
      expect(message_line("->", "x2")).to be > message_line("->>", "x2")
    end
  end
end
