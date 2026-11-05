# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Style::Reader do
  def sheet(*lines)
    described_class.read("@startuml\n#{lines.join("\n")}\n@enduml\n")
  end

  describe "the layers" do
    it "answers PlantUML's own look when the source sets nothing" do
      expect(sheet.resolve(:state, :background)).to eq("#F1F1F1")
    end

    it "lets skinparam beat the default" do
      expect(sheet("skinparam stateBackgroundColor pink")
        .resolve(:state, :background)).to eq("#FFC0CB")
    end

    it "lets <style> beat skinparam" do
      result = sheet("skinparam stateBackgroundColor pink", "<style>",
                     "state {", "BackgroundColor #00f", "}", "</style>")

      expect(result.resolve(:state, :background)).to eq("#0000FF")
    end

    it "lets an element's own colour beat <style>" do
      result = sheet("<style>", "state {", "BackgroundColor #00f", "}",
                     "</style>").with_element("A", background: "#FF0000")

      expect(result.resolve(:state, :background, id: "A")).to eq("#FF0000")
    end

    it "merges a second set of properties written for the same element" do
      first = sheet.with_element("A", background: "#FF0000")
      result = first.with_element("A", border: "#0000FF")

      expect([result.resolve(:state, :background, id: "A"),
              result.resolve(:state, :border, id: "A")])
        .to eq(%w[#FF0000 #0000FF])
    end

    it "keeps one element's colour off its neighbour" do
      result = sheet.with_element("A", background: "#FF0000")

      expect(result.resolve(:state, :background, id: "B")).to eq("#F1F1F1")
    end
  end

  describe "skinparam" do
    it "reads the block form as the element's properties" do
      result = sheet("skinparam class {", "BackgroundColor LightYellow",
                     "BorderColor Navy", "FontName Courier", "}")

      expect(%i[background border font_name].map do |property|
        result.resolve(:class, property)
      end).to eq(["#FFFFE0", "#000080", "Courier"])
    end

    it "reads ArrowColor inside a state block as the arrow's" do
      result = sheet("skinparam state {", "ArrowColor Red", "}")

      expect(result.resolve(:arrow, :border)).to eq("#FF0000")
    end

    it "reads a global RoundCorner for every element" do
      expect(sheet("skinparam roundCorner 5").resolve(:class, :round_corner))
        .to eq(5.0)
    end

    it "reads a stereotyped rule only for that stereotype" do
      result = sheet("skinparam stateBackgroundColor<<hot>> red")

      expect([nil, "hot"].map do |stereotype|
        result.resolve(:state, :background, stereotype: stereotype)
      end).to eq(["#F1F1F1", "#FF0000"])
    end

    it "reads backgroundColor as the canvas" do
      expect(sheet("skinparam backgroundColor #EEE")
        .resolve(:document, :background)).to eq("#EEEEEE")
    end
  end

  describe "<style>" do
    it "reads dotted and dashed as the dash pattern PlantUML draws" do
      result = sheet("<style>", "state {", "LineStyle dotted", "}", "</style>")

      expect(result.resolve(:state, :line_style)).to eq("1,3")
    end

    it "reads a .stereotype rule" do
      result = sheet("<style>", "stateDiagram {", ".hot { FontColor red }",
                     "}", "</style>")

      expect(result.resolve(:state, :font_colour, stereotype: "hot"))
        .to eq("#FF0000")
    end

    it "reads the diagram selector as that family's element" do
      result = sheet("<style>", "activityDiagram {", "BackgroundColor #ccf",
                     "}", "</style>")

      expect(result.resolve(:activity, :background)).to eq("#CCCCFF")
    end
  end

  describe "a declaration's colours" do
    it "reads #fill;line:;text: and the stereotype" do
      result = sheet("state A <<hot>> #pink;line:blue;text:green")

      expect(result.element("A")).to eq(
        background: "#FFC0CB", border: "#0000FF", font_colour: "#008000",
        stereotype: "hot"
      )
    end

    it "reads ##[dashed]blue as a dashed blue line" do
      expect(sheet("state A ##[dashed]blue").element("A"))
        .to eq(border: "#0000FF", line_style: "7,7")
    end

    it "reads a class declaration's colour" do
      expect(sheet("class A #red").element("A"))
        .to eq(background: "#FF0000")
    end
  end

  describe ".styling?" do
    it "marks a skinparam line, its block and a style block" do
      lines = ["skinparam a b", "skinparam c {", "X y", "}", "<style>", "z",
               "</style>", "start"]

      expect(described_class.styling?(lines))
        .to eq([true, true, true, true, true, true, true, false])
    end
  end
end
